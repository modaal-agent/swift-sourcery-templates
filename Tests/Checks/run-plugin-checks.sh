#!/bin/bash
#
# Plugin checks — the build-tool plugin, black-box.
#
# A plugin target cannot be imported by a test target (spec 001 §1.5: a plugin
# may not depend on a library), so there is no unit test that can reach any of
# this file's types. Every gate below builds a fixture package and reads what the
# plugin wrote: the synthesized configs under `.sourceryConfigs/`, the generated
# code under `.generatedFiles/`, and the build's own success or failure.
#
#   green lane   Checks/PluginFixture — a package that must build, carrying one
#                target per config shape the spec defines, and a three-level
#                dependency chain (App → Middle → Leaf, with ExternalKit arriving
#                through Middle from a second package) so the closure has
#                something to reach that no env var can name.
#   red lane     Checks/PluginFixtureRed/* — five packages, each of which must
#                FAIL, for a reason this script matches on. One package per
#                control: build planning runs every target's plugin, so a
#                plan-time error in one target fails the build for all of them.
#   bundle route Checks/PluginFixtureBundleRoute — a package whose dependency is
#                a copy of this repository with no `templates/`, so the two
#                routes ahead of the artifact bundle cannot answer and the third
#                one runs. The only place it does.
#
# Usage:
#   Checks/run-plugin-checks.sh            # run the gates
#   Checks/run-plugin-checks.sh --keep     # keep the resolved dependencies AND
#                                          # the plugin outputs (faster, but the
#                                          # cold-cache gate no longer runs cold)
#
# Needs no simulator. It does need the toolchain and, once, the network: the
# fixtures resolve this package, which pulls swift-argument-parser and the pinned
# Sourcery artifact bundle. Both are cached under .build/plugin-checks/cache and
# reused by all five fixture packages.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_DIR="$GIT_ROOT/.build/plugin-checks"
CACHE_DIR="$WORK_DIR/cache"
FIXTURE_DIR="$SCRIPT_DIR/PluginFixture"
FIXTURE_SCRATCH="$WORK_DIR/fixture"
RED_DIR="$SCRIPT_DIR/PluginFixtureRed"
BUNDLE_ROUTE_DIR="$SCRIPT_DIR/PluginFixtureBundleRoute"
ENGINE_PACKAGE="$WORK_DIR/engine-package"

KEEP=0
[ "$1" = "--keep" ] && KEEP=1

mkdir -p "$CACHE_DIR"

FAILURES=0
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok: $1"; }

SWIFT_FLAGS=(--cache-path "$CACHE_DIR")

# ── Helpers ───────────────────────────────────────────────────────

# The synthesized copy of <config> for <target>.
synthesized() {
  find "$FIXTURE_SCRATCH/plugins/outputs" -path "*/$1/*/.sourceryConfigs/$2" -type f 2>/dev/null | head -1
}

# A file Sourcery generated for <target> from <config-directory>.
generated() {
  find "$FIXTURE_SCRATCH/plugins/outputs" -path "*/$1/*/.generatedFiles/$2/$3" -type f 2>/dev/null | head -1
}

# The lines of a `sources:`/`templates:` block that the plugin wrote: quoted
# absolute paths, one per line, unquoted here for legibility.
block_paths() {   # file key
  awk -v key="$2" '
    $0 ~ "^" key ":" { inblock = 1; next }
    /^[A-Za-z_]/     { inblock = 0 }
    inblock && /^[ \t]*- "/ {
      line = $0
      sub(/^[ \t]*- "/, "", line)
      sub(/"[ \t]*$/, "", line)
      print line
    }
  ' "$1"
}

# Every line of <original> is present in <synthesized>, in the same order, except
# the lines named after the two file arguments — which are exactly the lines the
# plugin is allowed to rewrite. This is the passthrough gate: a config's comments,
# blank lines and untouched keys have to survive byte for byte.
check_passthrough() {
  local original="$1" synthesized="$2"; shift 2
  local skiplist="$WORK_DIR/passthrough-rewritable"
  printf '%s\n' "$@" > "$skiplist"
  awk -v skipfile="$skiplist" -v origfile="$original" '
    FILENAME == skipfile { skip[$0] = 1; next }
    FILENAME == origfile { orig[++o] = $0; next }
    { syn[++s] = $0 }
    END {
      j = 1
      for (i = 1; i <= o; i++) {
        if (orig[i] in skip) continue
        found = 0
        while (j <= s) { if (syn[j++] == orig[i]) { found = 1; break } }
        if (!found) { print "missing or out of order: [" orig[i] "]"; exit 1 }
      }
    }
  ' "$skiplist" "$original" "$synthesized"
}

# ── 0. Typecheck both plugin API surfaces ─────────────────────────
# The fixture packages exercise the SPM path only. `XcodeBuildToolPlugin` lives
# behind `#if canImport(XcodeProjectPlugin)`, which is false in a package build —
# so without this gate the Xcode half of the file is never compiled by anything,
# and it degrades silently rather than safely. Xcode ships an XcodeProjectPlugin
# module beside SwiftPM; compiling against it is the whole check.
echo "── typecheck ──"
PLUGIN_SOURCE="$GIT_ROOT/Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift"
XCODE_PLUGIN_API="$(xcode-select -p)/../SharedFrameworks/SwiftPM.framework/Versions/A/SharedSupport/PluginAPI"
TOOLCHAIN_PLUGIN_API="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift/pm/PluginAPI"

typecheck_plugin() {   # label search-path
  local label="$1" search_path="$2"
  if [ ! -d "$search_path" ]; then
    echo "  skipped $label: no PluginAPI at $search_path"
    return
  fi
  local log="$WORK_DIR/typecheck-$label.log"
  # -package-description-version is what SwiftPM passes; without it the API's
  # own availability annotations make `sourceModule` and friends unavailable.
  if xcrun swiftc -typecheck -swift-version 5 \
       -I "$search_path" \
       -package-description-version 5.9 \
       -parse-as-library \
       "$PLUGIN_SOURCE" > "$log" 2>&1; then
    pass "$label: clean"
  else
    head -20 "$log"
    fail "$label: the plugin does not compile against this PluginAPI"
  fi
}

mkdir -p "$WORK_DIR"
typecheck_plugin "spm-only" "$TOOLCHAIN_PLUGIN_API"
typecheck_plugin "with-xcodeprojectplugin" "$XCODE_PLUGIN_API"
echo ""

# ── 1. Build the green fixture, cold ──────────────────────────────
echo "── building the fixture ──"
if [ "$KEEP" = "0" ]; then
  # Keep the resolved dependencies and the downloaded artifact bundle; drop
  # everything the plugin produced, so the caches below really are cold.
  rm -rf "$FIXTURE_SCRATCH/plugins/outputs"
fi

BUILD_LOG="$WORK_DIR/fixture-build.log"
mkdir -p "$WORK_DIR"
COLD_START=$SECONDS
if ! swift build --package-path "$FIXTURE_DIR" --scratch-path "$FIXTURE_SCRATCH" \
      "${SWIFT_FLAGS[@]}" --build-tests -v > "$BUILD_LOG" 2>&1; then
  tail -30 "$BUILD_LOG"
  echo "FAIL: the fixture package did not build — every gate below depends on it"
  exit 1
fi
COLD_SECONDS=$((SECONDS - COLD_START))
echo "  built in ${COLD_SECONDS}s (cold plugin outputs)"

APP_CONFIG="$(synthesized App .Sourcery.App.yml)"
SOLO_CONFIG="$(synthesized Solo .Sourcery.Solo.yml)"
VERBATIM_CONFIG="$(synthesized Verbatim .Sourcery.Verbatim.yml)"
LOCAL_CONFIG="$(synthesized Local .Sourcery.Local.yml)"
APPTESTS_MOCKS="$(synthesized AppTests .Sourcery.Mocks.yml)"
APPTESTS_PRESET="$(synthesized AppTests .Sourcery.Preset.yml)"
AMBIGUOUS_CONFIG="$(synthesized AmbiguousTests .Sourcery.Mocks.yml)"

for f in "$APP_CONFIG" "$SOLO_CONFIG" "$VERBATIM_CONFIG" "$LOCAL_CONFIG" \
         "$APPTESTS_MOCKS" "$APPTESTS_PRESET" "$AMBIGUOUS_CONFIG"; do
  [ -n "$f" ] && [ -f "$f" ] || { echo "FAIL: the plugin wrote no synthesized config where one was expected"; exit 1; }
done

# ── 2. Splice ─────────────────────────────────────────────────────
# The closure App reaches is App, Middle, Leaf and ExternalKit. Leaf is two
# levels down and ExternalKit two levels down in another package: neither has a
# SOURCERY_TARGET_* var, so neither could be listed before this spec.
echo ""
echo "── splice ──"
APP_SOURCES="$(block_paths "$APP_CONFIG" sources)"
for module in App Middle Leaf ExternalKit; do
  if printf '%s\n' "$APP_SOURCES" | grep -qE "/$module\$"; then
    pass "the closure reached $module"
  else
    fail "the closure is missing $module"
  fi
done
if [ "$(printf '%s\n' "$APP_SOURCES" | wc -l | tr -d ' ')" = "4" ]; then
  pass "four directories, one per source module"
else
  fail "expected four directories, got: $(printf '%s\n' "$APP_SOURCES" | tr '\n' ' ')"
fi
if [ "$APP_SOURCES" = "$(printf '%s\n' "$APP_SOURCES" | LC_ALL=C sort)" ]; then
  pass "sorted lexicographically"
else
  fail "the spliced directories are not sorted — the config is not stable between resolutions"
fi
if printf '%s\n' "$APP_SOURCES" | grep -qv '^/'; then
  fail "a spliced source entry is not an absolute path"
else
  pass "every spliced entry is absolute"
fi
# The author's own entry survives beside the derived ones.
if grep -qF '${SOURCERY_TARGET_App}   # a subset the plugin must not decide, listed by hand' "$APP_CONFIG"; then
  pass "the hand-listed entry beside the placeholder is untouched, comment and all"
else
  fail "the hand-listed source entry did not survive the splice"
fi

# ── 3. Passthrough ────────────────────────────────────────────────
echo ""
echo "── passthrough ──"
if check_passthrough "$FIXTURE_DIR/Sources/App/.Sourcery.App.yml" "$APP_CONFIG" \
     '  - ${SOURCERY_SOURCES}' '  - Mocks' '  - Component'; then
  pass "every line but the placeholder and the two template names is carried through verbatim"
else
  fail "the synthesized config does not carry the author's lines through"
fi

# ── 4. Defaults ───────────────────────────────────────────────────
# A config that says only what to generate is a complete config: `sources:` and
# `output:` are mandatory to Sourcery and have one right answer each (§4.6).
echo ""
echo "── defaults ──"
SOLO_SOURCES="$(block_paths "$SOLO_CONFIG" sources)"
if [ "$SOLO_SOURCES" = "$FIXTURE_DIR/Sources/Solo" ]; then
  pass "sources: appended, holding the closure"
else
  fail "sources: was not appended as expected (got '$SOLO_SOURCES')"
fi
SOLO_OUTPUT="$(grep '^output:' "$SOLO_CONFIG" | sed 's/^output: "//; s/"$//')"
if [ -d "$SOLO_OUTPUT" ] && [ -f "$SOLO_OUTPUT/Mocks.generated.swift" ]; then
  pass "output: appended as an absolute path, and Sourcery generated into it"
else
  fail "output: was not appended to an existing directory holding the generated file (got '$SOLO_OUTPUT')"
fi
if grep -q 'class GreetingMock' "$SOLO_OUTPUT/Mocks.generated.swift" 2>/dev/null; then
  pass "the zero-configuration target generated its mock"
else
  fail "the zero-configuration target generated no mock"
fi

# ── 5. No-defaults ────────────────────────────────────────────────
# A config that declares its inputs and its output keeps them — including one
# that declares `package:` rather than `sources:`, which Sourcery accepts in its
# place. Appending over either would override a deliberate choice, silently.
echo ""
echo "── no-defaults ──"
if diff -q "$FIXTURE_DIR/Sources/Verbatim/.Sourcery.Verbatim.yml" "$VERBATIM_CONFIG" > /dev/null; then
  pass "a config declaring everything comes out byte-identical"
else
  diff -u "$FIXTURE_DIR/Sources/Verbatim/.Sourcery.Verbatim.yml" "$VERBATIM_CONFIG" | head -20
  fail "a config declaring everything was rewritten"
fi

# ── 6. Testable ───────────────────────────────────────────────────
echo ""
echo "── testable ──"
if grep -qx '  testable: \[App\]' "$APPTESTS_MOCKS"; then
  pass "one direct root-package dependency: testable inserted at the siblings' indentation"
else
  fail "testable was not inserted for the unambiguous test target"
  grep -A3 '^args:' "$APPTESTS_MOCKS" || true
fi
if diff -q "$FIXTURE_DIR/Tests/AppTests/.Sourcery.Preset.yml" \
           <(sed 's|^templates:|templates:|' "$APPTESTS_PRESET") > /dev/null 2>&1 \
   || [ "$(grep -cE '^[[:space:]]*testable[[:space:]]*:' "$APPTESTS_PRESET")" = "1" ]; then
  pass "a config that already names testable is left alone"
else
  fail "a config that already declares testable was edited"
fi
if grep -qE '^[[:space:]]*testable[[:space:]]*:' "$AMBIGUOUS_CONFIG"; then
  fail "testable was inserted for a test target with two candidate modules"
else
  pass "two candidates: nothing inserted"
fi
if grep -qE 'AmbiguousTests.*directly depends on 2 root-package modules \(App, Solo\)' "$BUILD_LOG" \
   || grep -qE 'directly depends on 2 root-package modules \(App, Solo\)' "$BUILD_LOG"; then
  pass "and the build log names both candidates"
else
  fail "the build log does not name the two candidate modules"
fi
for target_config in "$APP_CONFIG" "$SOLO_CONFIG" "$LOCAL_CONFIG"; do
  if grep -qE '^[[:space:]]*testable[[:space:]]*:' "$target_config"; then
    fail "testable was inserted into a non-test target's config ($target_config)"
  fi
done
pass "no non-test target got a testable"

# ── 7. Bare names ─────────────────────────────────────────────────
echo ""
echo "── bare name ──"
APP_TEMPLATES="$(block_paths "$APP_CONFIG" templates)"
if [ "$APP_TEMPLATES" = "$GIT_ROOT/templates/Mocks.swifttemplate
$GIT_ROOT/templates/Component.swifttemplate" ]; then
  pass "- Mocks and - Component resolved to the shipped files, in the order written"
else
  fail "bare template names did not resolve to the shipped templates (got: $APP_TEMPLATES)"
fi
LOCAL_TEMPLATE="$(block_paths "$LOCAL_CONFIG" templates)"
if [ "$LOCAL_TEMPLATE" = "$FIXTURE_DIR/Sources/Local/Mocks.swifttemplate" ]; then
  pass "a template beside the config wins over the shipped one of the same name"
else
  fail "the template beside the config did not win (got '$LOCAL_TEMPLATE')"
fi
LOCAL_OUT="$(generated Local Sourcery.Local Mocks.generated.swift)"
if [ -n "$LOCAL_OUT" ] && grep -q 'PLUGIN-FIXTURE-LOCAL-TEMPLATE' "$LOCAL_OUT"; then
  pass "and it is the local template that ran"
else
  fail "the shipped Mocks template ran where the local one should have"
fi

# ── 8. Generation ─────────────────────────────────────────────────
# The §6.1 failure, at fast-lane speed: `ProfilePersisting` refines `Caching`
# (Middle), `Persisting` (Leaf, two levels) and `Reporting` (ExternalKit, two
# levels and another package). A mock missing any of them does not compile, and
# the specs below assert it records.
echo ""
echo "── generation ──"
APP_MOCK="$(generated App Sourcery.App Mocks.generated.swift)"
if [ -z "$APP_MOCK" ]; then
  fail "no mock was generated for App"
else
  for requirement in "func save(" "func report(" "var cacheLimit" "var profileID"; do
    if grep -qF "$requirement" "$APP_MOCK"; then
      pass "the mock carries '$requirement'"
    else
      fail "the mock is missing '$requirement' — the closure did not reach the module declaring it"
    fi
  done
fi
if [ -n "$(generated App Sourcery.App Component.generated.swift)" ]; then
  pass "one config, two templates, two generated files"
else
  fail "the second template of App's config generated nothing"
fi
if swift test --package-path "$FIXTURE_DIR" --scratch-path "$FIXTURE_SCRATCH" \
     "${SWIFT_FLAGS[@]}" > "$WORK_DIR/fixture-test.log" 2>&1; then
  pass "the fixture's specs pass against the generated mock"
else
  tail -20 "$WORK_DIR/fixture-test.log"
  fail "the fixture's specs did not pass"
fi

# ── 9. Determinism ────────────────────────────────────────────────
# The prebuild command re-runs on every build, so whatever the plugin writes at
# plan time has to be byte-identical between runs that resolve the same graph, or
# Sourcery's cache is invalidated every time (§1.5).
echo ""
echo "── determinism ──"
SNAPSHOT="$WORK_DIR/configs-before"
rm -rf "$SNAPSHOT"; mkdir -p "$SNAPSHOT"
i=0
while IFS= read -r config; do
  i=$((i + 1))
  cp "$config" "$SNAPSHOT/$i-$(basename "$config")"
done < <(find "$FIXTURE_SCRATCH/plugins/outputs" -path "*/.sourceryConfigs/*" -type f | sort)

WARM_START=$SECONDS
swift build --package-path "$FIXTURE_DIR" --scratch-path "$FIXTURE_SCRATCH" \
  "${SWIFT_FLAGS[@]}" --build-tests > "$WORK_DIR/fixture-rebuild.log" 2>&1
WARM_SECONDS=$((SECONDS - WARM_START))

DRIFT=0
i=0
while IFS= read -r config; do
  i=$((i + 1))
  if ! diff -q "$SNAPSHOT/$i-$(basename "$config")" "$config" > /dev/null; then
    diff -u "$SNAPSHOT/$i-$(basename "$config")" "$config" | head -10
    DRIFT=$((DRIFT + 1))
  fi
done < <(find "$FIXTURE_SCRATCH/plugins/outputs" -path "*/.sourceryConfigs/*" -type f | sort)
if [ "$DRIFT" = "0" ]; then
  pass "$i synthesized configs, all byte-identical on a second build (warm: ${WARM_SECONDS}s)"
else
  fail "$DRIFT synthesized config(s) changed between two builds of the same graph"
fi

# ── 10. The shared per-target cache and build directory ────────────
# Open question from §7, measured rather than argued: a target's configs share one
# --cacheBasePath and one --buildPath. AppTests carries two. Build it again and
# report whether the two runs interfered — a Sourcery error, a cache-recovery
# line, or a change in what was generated.
echo ""
echo "── shared cache (two configs, one target) ──"
APPTESTS_MOCK_OUT="$(generated AppTests Sourcery.Mocks Mocks.generated.swift)"
APPTESTS_COMPONENT_OUT="$(generated AppTests Sourcery.Preset Component.generated.swift)"
if [ -n "$APPTESTS_MOCK_OUT" ] && [ -n "$APPTESTS_COMPONENT_OUT" ]; then
  pass "both configs of one target generated, into directories of their own"
else
  fail "a target with two configs did not produce both outputs"
fi
cp "$APPTESTS_MOCK_OUT" "$WORK_DIR/apptests-mocks-before" 2>/dev/null || true
cp "$APPTESTS_COMPONENT_OUT" "$WORK_DIR/apptests-component-before" 2>/dev/null || true
INTERFERENCE=0
for run in 1 2; do
  rm -rf "$FIXTURE_SCRATCH"/plugins/outputs/*/AppTests/*/SourcerySwiftCodegenPlugin/.sourceryCaches
  swift build --package-path "$FIXTURE_DIR" --scratch-path "$FIXTURE_SCRATCH" \
    "${SWIFT_FLAGS[@]}" --build-tests > "$WORK_DIR/fixture-shared-cache-$run.log" 2>&1 \
    || { fail "build $run of the two-config target failed"; INTERFERENCE=1; }
  if grep -qiE "recovering with a full rebuild|cache.*corrupt" "$WORK_DIR/fixture-shared-cache-$run.log"; then
    fail "run $run reported a cache problem"
    INTERFERENCE=1
  fi
done
if ! diff -q "$WORK_DIR/apptests-mocks-before" "$(generated AppTests Sourcery.Mocks Mocks.generated.swift)" > /dev/null \
   || ! diff -q "$WORK_DIR/apptests-component-before" "$(generated AppTests Sourcery.Preset Component.generated.swift)" > /dev/null; then
  fail "the two configs of one target produced different output on a rebuild"
  INTERFERENCE=1
fi
[ "$INTERFERENCE" = "0" ] && pass "two cold-cache rebuilds, no interference between the two configs"

# ── 11. Red controls ──────────────────────────────────────────────
# Each of these must fail, and fail for the reason named. A red control that
# stops failing is a gate that stopped gating.
echo ""
echo "── red controls ──"
red_control() {   # name expected-pattern description
  local name="$1" pattern="$2" description="$3"
  local log="$WORK_DIR/red-$name.log"
  if swift build --package-path "$RED_DIR/$name" --scratch-path "$WORK_DIR/red/$name" \
       "${SWIFT_FLAGS[@]}" > "$log" 2>&1; then
    fail "$name built, and it must not: $description"
    return
  fi
  if grep -qE "$pattern" "$log"; then
    pass "$name fails: $description"
  else
    tail -15 "$log"
    fail "$name failed, but not with the expected diagnostic ($pattern)"
  fi
}

red_control WrongOutput \
  "\`output:\` resolves to '/tmp/plugin-fixture-red-wrong-output', but the build collects generated files only from" \
  "an output: the build does not collect from is named, with both paths, and stops the build"
red_control Collision \
  "\.Sourcery\.First\.yml and \.Sourcery\.Second\.yml both generate 'Mocks\.generated\.swift'" \
  "two configs of one target naming one template are refused by name, not silently overwritten"
red_control UnknownTemplate \
  "template 'Mocsk' is neither a file beside the config nor a shipped template" \
  "an unresolvable template name warns, lists the shipped templates, and then fails"
red_control NearMiss \
  '`protocolmock` on `NearMissProtocol` is not `ProtocolMock`' \
  "a selector that differs only in case fails generation, naming the type and the canonical spelling"
red_control PackageKey \
  "Invalid sources|fatalError|package" \
  "a config declaring package: is left alone and fails on its own terms"

# ...and the last one has a second half: the plugin must not have appended
# `sources:` over the author's `package:`.
PACKAGEKEY_CONFIG="$(find "$WORK_DIR/red/PackageKey" -path "*/.sourceryConfigs/*" -type f 2>/dev/null | head -1)"
if [ -n "$PACKAGEKEY_CONFIG" ] && ! grep -q '^sources:' "$PACKAGEKEY_CONFIG"; then
  pass "and no sources: block was appended over the author's package:"
elif [ -z "$PACKAGEKEY_CONFIG" ]; then
  fail "PackageKey wrote no synthesized config to inspect"
else
  fail "a sources: block was appended over a config that declares package:"
fi

# ── 12. The artifact-bundle template route ────────────────────────
# Route 3 of followup-xcode-lane.md §12, and the only gate that runs it. Every
# other fixture reaches this repository directly, so the plugin's own source file
# sits beside a `templates/` directory and route 2 answers first — which is what
# §16 wants on a branch, and what leaves route 3 covered by nothing.
#
# So the dependency here is a copy of this repository with `templates/` left out:
# route 1 finds the package in the graph with no templates under it, route 2
# finds none beside the plugin source, and the plugin falls through to the
# artifact bundle its manifest pins. `-v` because a remark reaches the SwiftPM
# log only in verbose mode.
echo ""
echo "── artifact-bundle route ──"
rm -rf "$ENGINE_PACKAGE"
mkdir -p "$ENGINE_PACKAGE"
cp "$GIT_ROOT/Package.swift" "$ENGINE_PACKAGE/"
cp -R "$GIT_ROOT/Plugins" "$GIT_ROOT/Sources" "$ENGINE_PACKAGE/"
if [ -e "$ENGINE_PACKAGE/templates" ]; then
  fail "the engine-package copy carries templates/, so this gate would test route 2 again"
fi

BUNDLE_ROUTE_SCRATCH="$WORK_DIR/bundle-route"
BUNDLE_ROUTE_LOG="$WORK_DIR/bundle-route.log"
if ! swift build --package-path "$BUNDLE_ROUTE_DIR" --scratch-path "$BUNDLE_ROUTE_SCRATCH" \
     "${SWIFT_FLAGS[@]}" -v > "$BUNDLE_ROUTE_LOG" 2>&1; then
  grep -E "error:" "$BUNDLE_ROUTE_LOG" | head -10
  fail "the bundle-route fixture did not build — a bare name did not resolve without a templates/ in the checkout"
else
  pass "a bare template name resolves with no templates/ in the consumed checkout"
  if grep -qF "shipped templates come from the pinned artifact bundle" "$BUNDLE_ROUTE_LOG"; then
    pass "and the log names the artifact bundle as the route"
  else
    grep -o "shipped templates come from [^\"]*" "$BUNDLE_ROUTE_LOG" | head -1
    fail "the log does not name the pinned artifact bundle as the route"
  fi
  BUNDLE_ROUTE_CONFIG="$(find "$BUNDLE_ROUTE_SCRATCH/plugins/outputs" -path "*/.sourceryConfigs/*" -type f 2>/dev/null | head -1)"
  BUNDLE_ROUTE_TEMPLATE="$(block_paths "$BUNDLE_ROUTE_CONFIG" templates)"
  case "$BUNDLE_ROUTE_TEMPLATE" in
    */artifacts/*.artifactbundle/templates/Mocks.swifttemplate)
      pass "'- Mocks' resolved inside the artifact bundle, not in this working tree" ;;
    *)
      fail "expected a path inside an .artifactbundle, got: $BUNDLE_ROUTE_TEMPLATE" ;;
  esac
  BUNDLE_ROUTE_MOCK="$(find "$BUNDLE_ROUTE_SCRATCH/plugins/outputs" -path "*/.generatedFiles/*/Mocks.generated.swift" -type f 2>/dev/null | head -1)"
  if [ -n "$BUNDLE_ROUTE_MOCK" ] && grep -q 'func ferry' "$BUNDLE_ROUTE_MOCK"; then
    pass "and the bundle's template generated the requirement the fixture declares"
  else
    fail "no mock, or one missing 'func ferry', from the bundle's template"
  fi
fi

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" = "0" ]; then
  echo "ALL PLUGIN CHECKS PASSED  (cold ${COLD_SECONDS}s, warm ${WARM_SECONDS}s)"
else
  echo "$FAILURES CHECK(S) FAILED"
  exit 1
fi
