#!/bin/bash
#
# print-mocks.sh — prints what SourcerySwiftCodegenPlugin generates for one target, without compiling
# the target.
#
#   print-mocks.sh <Target> [<Protocol> ...]
#
# Run it from the directory holding Package.swift, or from the one holding the .xcodeproj or
# .xcworkspace. <Target> is the target that applies the plugin and carries the config: the test
# target, for mocks. With protocol names it prints each protocol's `// MARK: - <Protocol>` block of
# the generated files; with none, every generated file of the target after a `// <path>` line.
#
# SwiftPM: `swift build --target <Target> --print-manifest-job-graph` plans the build, which runs the
#   plugin's prebuild command and compiles nothing, and the files are read from the build directory's
#   plugins/outputs. A package whose platforms rule out the host is planned for the iOS simulator.
# Xcode: re-runs the Sourcery engine on the configs the plugin synthesized at the target's last build,
#   with `output:` pointed at <DerivedData>/Build/Intermediates.noindex/PrintMocks. Needs one earlier
#   build of the target in that derived data.
#
# Environment, each optional:
#   SCRATCH_PATH        SwiftPM: the build directory, when it is not .build
#   DERIVED_DATA        Xcode: the derived data directory to read; setting it selects the Xcode lane
#   DERIVED_DATA_ROOT   Xcode: where to look for it, ~/Library/Developer/Xcode/DerivedData by default
#   SOURCERY_PROJECT    Xcode: the project directory, when it is not the one holding the .xcodeproj
#   PRINT_MOCKS_ENGINE  Xcode: the sourcery binary, when it is not found beside the templates the
#                       configs name or under <DerivedData>/SourcePackages
#
# The plan and the measurements behind it: specs/005-print-mock-without-build/spec.md in
# https://github.com/modaal-agent/swift-sourcery-templates.

set -eo pipefail

usage() { echo "usage: print-mocks.sh <Target> [<Protocol> ...]" >&2; exit 2; }
[ $# -ge 1 ] || usage
TARGET="$1"; shift
PROTOCOLS=("$@")

fail() { echo "print-mocks: $*" >&2; exit 1; }

# The first line of the input. awk reads to the end, so the command writing into the pipe is not
# stopped by SIGPIPE, which `set -o pipefail` would turn into a silent exit.
first() { awk 'NR == 1'; }

# ── printing ──────────────────────────────────────────────────────

print_generated() {   # <file>...
  [ $# -gt 0 ] || fail "$TARGET generated no file — does it apply SourcerySwiftCodegenPlugin and carry a *.sourcery*.yml config?"
  if [ ${#PROTOCOLS[@]} -eq 0 ]; then
    for file in "$@"; do
      echo "// $file"
      cat "$file"
      echo
    done
    return
  fi
  missing=0
  for protocol in "${PROTOCOLS[@]}"; do
    # A mock is its `// MARK: - <Protocol>` line through the first `}` at column 0.
    block="$(awk -v p="$protocol" '$0 == "// MARK: - " p { on = 1 } on { print } on && /^}/ { exit }' "$@")"
    if [ -z "$block" ]; then
      echo "// $protocol: no mock generated for $TARGET"
      missing=$((missing + 1))
    else
      printf '%s\n\n' "$block"
    fi
  done
  total=${#PROTOCOLS[@]}
  [ "$missing" -eq 0 ] || fail "$missing of $total protocols have no mock in $TARGET's generated files"
}

# ── SwiftPM ───────────────────────────────────────────────────────

spm() {
  build=".build"
  scratch=()
  if [ -n "${SCRATCH_PATH:-}" ]; then
    build="$SCRATCH_PATH"
    scratch=(--scratch-path "$SCRATCH_PATH")
  fi
  err="$(mktemp)"
  trap 'rm -f "$err"' EXIT
  if ! swift build --target "$TARGET" --print-manifest-job-graph ${scratch[@]+"${scratch[@]}"} > /dev/null 2> "$err"; then
    # A package declaring no macOS platform cannot be planned for the host once it depends on the
    # plugin, which requires macOS 13. The simulator plan runs the same prebuild command.
    if grep -q "depends on the product 'SourcerySwiftCodegenPlugin' which requires macos" "$err"; then
      swift build --target "$TARGET" --print-manifest-job-graph ${scratch[@]+"${scratch[@]}"} \
        --triple "$(uname -m)-apple-ios-simulator" --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
        > /dev/null 2> "$err" || { cat "$err" >&2; fail "planning $TARGET for the iOS simulator failed"; }
    else
      cat "$err" >&2
      fail "planning $TARGET failed"
    fi
  fi
  # The plugin warns when the package is not in a git repository; every other warning is passed on.
  grep 'warning:' "$err" | grep -v 'Error running git command' >&2 || true

  files=()
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$build/plugins/outputs" -path "*/$TARGET/destination/SourcerySwiftCodegenPlugin/.generatedFiles/*" \
      -name '*.generated.swift' -type f 2>/dev/null | sort)
  print_generated ${files[@]+"${files[@]}"}
}

# ── Xcode ─────────────────────────────────────────────────────────

# The .sourceryConfigs directory the plugin wrote for $TARGET most recently: in $DERIVED_DATA when it
# is set, otherwise in each derived data directory whose workspace sits under the working directory.
synthesized_configs() {
  here="$(pwd -P)"
  {
    if [ -n "${DERIVED_DATA:-}" ]; then
      echo "$DERIVED_DATA"
    else
      for plist in "${DERIVED_DATA_ROOT:-$HOME/Library/Developer/Xcode/DerivedData}"/*/info.plist; do
        [ -f "$plist" ] || continue
        workspace="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$plist" 2>/dev/null)" || continue
        directory="$(cd "$(dirname "$workspace")" 2>/dev/null && pwd -P)" || continue
        case "$directory/" in "$here/"*) dirname "$plist" ;; esac
      done
    fi
  } | while IFS= read -r dd; do
    find "$dd/Build/Intermediates.noindex/BuildToolPluginIntermediates" -type d \
      -path "*/$TARGET/SourcerySwiftCodegenPlugin/.sourceryConfigs" 2>/dev/null || true
  done | while IFS= read -r dir; do
    printf '%s\t%s\n' "$(stat -f %m "$dir")" "$dir"
  done | sort -rn | awk -F'\t' 'NR == 1 { print $2 }'
}

xcode() {
  where="${DERIVED_DATA:-${DERIVED_DATA_ROOT:-$HOME/Library/Developer/Xcode/DerivedData}}"
  configs="$(synthesized_configs)"
  [ -n "$configs" ] || fail "no configs the plugin synthesized for $TARGET under $where — build $TARGET once, or set DERIVED_DATA"
  dd="${configs%%/Build/Intermediates.noindex/*}"
  workspace="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$dd/info.plist" 2>/dev/null || true)"
  project="${SOURCERY_PROJECT:-$(dirname "${workspace:-$(pwd)/.}")}"

  # The plugin keeps the author's file name, and `.Sourcery.Mocks.yml` is a dotfile a glob skips.
  config_files=()
  while IFS= read -r file; do config_files+=("$file"); done < <(find "$configs" -maxdepth 1 -type f | sort)
  [ ${#config_files[@]} -gt 0 ] || fail "$configs holds no config"

  # The engine: beside the shipped templates a config names by absolute path — an artifact bundle
  # holds both, and a package checkout's SourcePackages holds the bundle under artifacts/ — else
  # under this derived data's own SourcePackages.
  template="$(grep -ho '"[^"]*/templates/[^"/]*\.swifttemplate"' "${config_files[@]}" 2>/dev/null | first | tr -d '"')"
  templates_dir="${template:+$(dirname "$template")}"
  engine="${PRINT_MOCKS_ENGINE:-}"
  if [ -z "$engine" ] && [ -n "$templates_dir" ]; then
    root="$(dirname "$templates_dir")"
    if [ -f "$root/info.json" ]; then
      engine="$root/sourcery/bin/sourcery"
    else
      packages="${root%/checkouts/*}"
      engine="$(find "$packages/artifacts" -path '*/sourcery/bin/sourcery' -type f 2>/dev/null | first)"
    fi
  fi
  [ -n "$engine" ] || engine="$(find "$dd/SourcePackages/artifacts" -path '*/sourcery/bin/sourcery' -type f 2>/dev/null | first)"
  [ -n "$engine" ] && [ -x "$engine" ] || fail "no Sourcery engine found for $dd — set PRINT_MOCKS_ENGINE"
  if [ -z "$templates_dir" ] && [ -d "$(dirname "$engine")/../../templates" ]; then
    templates_dir="$(cd "$(dirname "$engine")/../../templates" && pwd)"
  fi

  work="$dd/Build/Intermediates.noindex/PrintMocks"
  rm -rf "${work:?}/$TARGET"
  mkdir -p "$work/$TARGET/.configs" "$work/.cache" "$work/.build"
  git_root="$(git -C "$project" rev-parse --show-toplevel 2>/dev/null || true)"
  for config in "${config_files[@]}"; do
    name="$(basename "$config")"
    # The output directory's name, as the plugin's directoryName(for:) derives it.
    stem="$name"; while [ "${stem#.}" != "$stem" ]; do stem="${stem#.}"; done; stem="${stem%.*}"
    out="$work/$TARGET/$stem"
    mkdir -p "$out"
    copy="$work/$TARGET/.configs/$name"
    awk -v o="$out" '/^output:/ { print "output: \"" o "\""; next } { print }' "$config" > "$copy"
    # The four variables the plugin's Xcode half exports to the engine.
    if ! env SOURCERY_PROJECT="$project" GIT_ROOT="$git_root" \
        SOURCERY_TEMPLATES="$templates_dir" SOURCERY_OUTPUT_DIR="$out" \
        "$engine" --config "$copy" --cacheBasePath "$work/.cache" --buildPath "$work/.build" --quiet \
        > "$copy.log" 2>&1; then
      cat "$copy.log" >&2
      fail "the engine failed on $name for $TARGET"
    fi
  done

  files=()
  while IFS= read -r file; do files+=("$file"); done < <(
    find "$work/$TARGET" -name '*.generated.swift' -type f -not -path '*/.configs/*' | sort)
  print_generated ${files[@]+"${files[@]}"}
}

# ── lane ──────────────────────────────────────────────────────────

if [ -n "${DERIVED_DATA:-}" ] || compgen -G '*.xcodeproj' > /dev/null || compgen -G '*.xcworkspace' > /dev/null; then
  xcode
elif [ -f Package.swift ]; then
  spm
else
  fail "run from the directory holding Package.swift or the .xcodeproj"
fi
