#!/bin/bash
#
# Assembles the release assets for one version, into .build/release-assets/:
#
#   swift-sourcery-templates-<version>.artifactbundle.zip
#       The full bundle: the vendored Sourcery engine (universal macOS
#       binary), this repo's templates/, and the mock-templates CLI. Its
#       info.json declares TWO executable artifacts — `sourcery` and
#       `mock-templates` — so a SwiftPM binaryTarget pointed at the zip
#       resolves either one by artifact name.
#   mock-templates-<version>-macos.zip
#       The CLI alone. A CI lane that only runs `validate` downloads
#       kilobytes instead of the ~60 MB engine.
#   <asset>.sha256
#       Beside each zip, in `shasum -a 256` format, so
#       `shasum -a 256 -c <asset>.sha256` verifies a download.
#   notes.md
#       The release-notes body the publish step attaches to the tag.
#
# The vendored engine's version, URL and checksum are parsed from the
# `sourcery` binaryTarget in Package.swift — the manifest is the only pin,
# and the downloaded zip is verified against the manifest checksum before
# anything is unpacked from it.
#
# The engine's bin/ejs.js is NOT vendored: it serves only .ejs templates,
# every template in this repo is a .swifttemplate, and the smoke test below
# runs generation with no ejs.js beside the binary — the control that keeps
# that true. It joins the bundle only if a template ever adopts .ejs.
#
# Usage:
#   Scripts/assemble-release.sh <version>     e.g. 0.6.0

set -eo pipefail

VERSION="$1"
[ -n "$VERSION" ] || { echo "usage: Scripts/assemble-release.sh <version>"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT="$GIT_ROOT/.build/release-assets"
rm -rf "$OUT"
mkdir -p "$OUT"

# ── The engine pin, from Package.swift ────────────────────────────
SOURCERY_URL="$(sed -n 's/.*url: "\(https[^"]*\.artifactbundle\.zip\)".*/\1/p' "$GIT_ROOT/Package.swift" | head -1)"
SOURCERY_CHECKSUM="$(sed -n 's/.*checksum: "\([0-9a-f]\{64\}\)".*/\1/p' "$GIT_ROOT/Package.swift" | head -1)"
SOURCERY_VERSION="$(echo "$SOURCERY_URL" | sed -n 's|.*/download/\([^/]*\)/.*|\1|p')"
[ -n "$SOURCERY_URL" ] && [ -n "$SOURCERY_CHECKSUM" ] && [ -n "$SOURCERY_VERSION" ] || {
  echo "FAIL: could not parse the sourcery binaryTarget's url/checksum from Package.swift"
  exit 1
}
echo "── engine ── Sourcery $SOURCERY_VERSION"

ENGINE_ZIP="$OUT/sourcery-upstream.zip"
# The check lanes cache the same zip; reuse it when its checksum matches.
CACHED="$GIT_ROOT/.build/sourcery-$SOURCERY_VERSION/sourcery.zip"
if [ -f "$CACHED" ] && echo "$SOURCERY_CHECKSUM  $CACHED" | shasum -a 256 -c - >/dev/null 2>&1; then
  cp "$CACHED" "$ENGINE_ZIP"
else
  curl -fsSL -o "$ENGINE_ZIP" "$SOURCERY_URL"
fi
echo "$SOURCERY_CHECKSUM  $ENGINE_ZIP" | shasum -a 256 -c - || {
  echo "FAIL: the downloaded engine zip does not match Package.swift's checksum"
  exit 1
}
unzip -q "$ENGINE_ZIP" -d "$OUT/engine"
ENGINE_ROOT="$OUT/engine/sourcery-$SOURCERY_VERSION.artifactbundle/sourcery"
[ -x "$ENGINE_ROOT/bin/sourcery" ] || { echo "FAIL: no engine executable under $ENGINE_ROOT"; exit 1; }

# ── The CLI, universal ────────────────────────────────────────────
echo "── build ── mock-templates (release, arm64 + x86_64)"
swift build --package-path "$GIT_ROOT" -c release --arch arm64 --arch x86_64 --product mock-templates
CLI="$GIT_ROOT/.build/apple/Products/Release/mock-templates"
[ -x "$CLI" ] || { echo "FAIL: no executable at $CLI"; exit 1; }

for BIN in "$CLI" "$ENGINE_ROOT/bin/sourcery"; do
  ARCHS="$(lipo -archs "$BIN")"
  case "$ARCHS" in
    *arm64*x86_64* | *x86_64*arm64*) ;;
    *) echo "FAIL: $BIN is not universal (archs: $ARCHS)"; exit 1 ;;
  esac
done

# ── Assemble the bundle ───────────────────────────────────────────
BUNDLE_NAME="swift-sourcery-templates-$VERSION.artifactbundle"
BUNDLE="$OUT/stage/$BUNDLE_NAME"
mkdir -p "$BUNDLE/sourcery/bin" "$BUNDLE/mock-templates/bin"

cp "$ENGINE_ROOT/bin/sourcery" "$BUNDLE/sourcery/bin/sourcery"
cp "$ENGINE_ROOT/LICENSE" "$BUNDLE/sourcery/LICENSE"
cp "$CLI" "$BUNDLE/mock-templates/bin/mock-templates"
cp -R "$GIT_ROOT/templates" "$BUNDLE/templates"
cp "$GIT_ROOT/LICENSE.txt" "$BUNDLE/LICENSE.txt"

cat > "$BUNDLE/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "sourcery": {
      "type": "executable",
      "version": "$SOURCERY_VERSION",
      "variants": [
        {
          "path": "sourcery/bin/sourcery",
          "supportedTriples": ["x86_64-apple-macosx", "arm64-apple-macosx"]
        }
      ]
    },
    "mock-templates": {
      "type": "executable",
      "version": "$VERSION",
      "variants": [
        {
          "path": "mock-templates/bin/mock-templates",
          "supportedTriples": ["x86_64-apple-macosx", "arm64-apple-macosx"]
        }
      ]
    }
  }
}
EOF
python3 -m json.tool "$BUNDLE/info.json" >/dev/null || { echo "FAIL: info.json is not valid JSON"; exit 1; }

# ── Smoke: the assembled layout generates and validates ──────────
# Same invocation as Tests/Checks/run-cli-checks.sh, but every path is the
# bundle's own: its engine (with no ejs.js beside it), its templates/, its
# CLI. Proves the three pieces work from the shipped layout before zipping.
echo "── smoke ──"
SMOKE="$OUT/smoke"
mkdir -p "$SMOKE"
"$BUNDLE/sourcery/bin/sourcery" --version | grep -q "$SOURCERY_VERSION" || {
  echo "FAIL: bundled engine does not report version $SOURCERY_VERSION"
  exit 1
}
"$BUNDLE/mock-templates/bin/mock-templates" generate \
  --sourcery "$BUNDLE/sourcery/bin/sourcery" \
  --templates "$BUNDLE/templates/Mocks.swifttemplate" \
  --sources "$GIT_ROOT/Tests/Checks/Fixtures" \
  --args "import=Combine,import=Foundation" \
  --bundle-version "$VERSION" \
  --root "$GIT_ROOT" \
  --output "$SMOKE/Mocks.generated.swift" \
  --disable-cache
"$BUNDLE/mock-templates/bin/mock-templates" validate \
  --file "$SMOKE/Mocks.generated.swift" \
  --root "$GIT_ROOT" \
  --sources "$GIT_ROOT/Tests/Checks/Fixtures" \
  --expect-bundle "$VERSION"

# ── Zip + checksums + notes ───────────────────────────────────────
echo "── package ──"
BUNDLE_ZIP="$BUNDLE_NAME.zip"
CLI_ZIP="mock-templates-$VERSION-macos.zip"

ditto -c -k --keepParent "$BUNDLE" "$OUT/$BUNDLE_ZIP"

CLI_STAGE="$OUT/stage/cli"
mkdir -p "$CLI_STAGE"
cp "$CLI" "$CLI_STAGE/mock-templates"
cp "$GIT_ROOT/LICENSE.txt" "$CLI_STAGE/LICENSE.txt"
(cd "$CLI_STAGE" && ditto -c -k . "$OUT/$CLI_ZIP.tmp" && mv "$OUT/$CLI_ZIP.tmp" "$OUT/$CLI_ZIP")

(cd "$OUT" && shasum -a 256 "$BUNDLE_ZIP" > "$BUNDLE_ZIP.sha256")
(cd "$OUT" && shasum -a 256 "$CLI_ZIP" > "$CLI_ZIP.sha256")
BUNDLE_SHA="$(cut -d' ' -f1 "$OUT/$BUNDLE_ZIP.sha256")"
CLI_SHA="$(cut -d' ' -f1 "$OUT/$CLI_ZIP.sha256")"

cat > "$OUT/notes.md" <<EOF
One download for a repo that generates: the artifact bundle carries the
Sourcery $SOURCERY_VERSION engine (universal macOS binary), this repository's
\`templates/\`, and the \`mock-templates\` CLI. Its \`info.json\` declares both
executables, so a SwiftPM \`binaryTarget\` pointed at the zip resolves
\`sourcery\` or \`mock-templates\` by artifact name.

| Asset | Contents |
| --- | --- |
| \`$BUNDLE_ZIP\` | engine + \`templates/\` + CLI |
| \`$CLI_ZIP\` | the CLI alone — enough for a \`validate\`-only CI lane |

SHA-256 (each also published beside its zip as \`.sha256\`):

\`\`\`
$BUNDLE_SHA  $BUNDLE_ZIP
$CLI_SHA  $CLI_ZIP
\`\`\`

The artifact bundle's SHA-256 doubles as the SwiftPM \`binaryTarget\`
checksum. See CHANGELOG.md for what changed in the generated output.
EOF

rm -rf "$OUT/stage" "$OUT/engine" "$OUT/smoke" "$ENGINE_ZIP"
echo ""
echo "Assembled in $OUT:"
(cd "$OUT" && ls -lh *.zip *.sha256 notes.md)
