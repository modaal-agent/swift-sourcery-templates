#!/bin/bash
#
# Refuses a release whose pinned artifact bundle carries templates other than
# this commit's.
#
# The plugin resolves `templates/` from three places (specs/001-plugin-source-
# discovery/followup-xcode-lane.md §12), and the third is the artifact bundle
# `Package.swift`'s `sourcery` binaryTarget pins. A `binaryTarget` names a URL
# and a checksum, so the asset has to exist before the commit that references
# it — which is why a release is cut in two tags:
#
#   templates-X.Y.Z at C    publishes the bundle built from C's templates/
#   X.Y.Z           at C'   where C' changes Package.swift and nothing else
#
# `C' changed only Package.swift` is a promise a person keeps, so this script
# is the check: it downloads the pinned bundle, verifies it against the
# manifest checksum, and compares its `templates/` with this commit's, byte for
# byte. A template edited between the two tags fails here rather than shipping
# a plugin whose bare template names resolve to a directory nobody reviewed.
#
# A release that changes only the plugin, the CLI or the docs needs no new
# templates tag: the pin stays where it is and this comparison passes, because
# `templates/` did not move.
#
# Usage:
#   Scripts/check-pinned-templates.sh          # compare and report

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WORK="$GIT_ROOT/.build/pinned-templates"
rm -rf "$WORK"
mkdir -p "$WORK"

# ── The pin, by name ──────────────────────────────────────────────
# `swift package dump-package` resolves the manifest and names each target, so
# the `sourcery` binaryTarget is read by name rather than by position in the
# file (Scripts/engine-pin.sh records what position cost).
PIN="$(swift package --package-path "$GIT_ROOT" dump-package | python3 -c '
import json, sys
package = json.load(sys.stdin)
for target in package["targets"]:
    if target["name"] == "sourcery" and target["type"] == "binary":
        print(target.get("url") or "")
        print(target.get("checksum") or "")
        break
')"
BUNDLE_URL="$(echo "$PIN" | sed -n 1p)"
BUNDLE_CHECKSUM="$(echo "$PIN" | sed -n 2p)"
[ -n "$BUNDLE_URL" ] && [ -n "$BUNDLE_CHECKSUM" ] || {
  echo "FAIL: Package.swift has no 'sourcery' binaryTarget with a url and a checksum."
  echo "      A binaryTarget declared with 'path:' has neither, and this gate"
  echo "      cannot compare a bundle it cannot download."
  exit 1
}
echo "── pin ── $BUNDLE_URL"

# ── Download and verify ───────────────────────────────────────────
ZIP="$WORK/pinned.zip"
curl -fsSL -o "$ZIP" "$BUNDLE_URL" || {
  echo "FAIL: could not download the pinned bundle from $BUNDLE_URL"
  exit 1
}
echo "$BUNDLE_CHECKSUM  $ZIP" | shasum -a 256 -c - || {
  echo "FAIL: the downloaded bundle does not match Package.swift's checksum"
  exit 1
}
unzip -q "$ZIP" -d "$WORK/unpacked"

# ── Find the bundle root and compare ──────────────────────────────
# The root is the directory holding info.json, for the reason the plugin uses
# the same test (F7): a component count is true of one layout and silently
# wrong of the next.
INFO="$(find "$WORK/unpacked" -maxdepth 3 -name info.json -type f | head -1)"
[ -n "$INFO" ] || { echo "FAIL: the pinned bundle holds no info.json"; exit 1; }
BUNDLE_ROOT="$(dirname "$INFO")"

PINNED_TEMPLATES="$BUNDLE_ROOT/templates"
[ -d "$PINNED_TEMPLATES" ] || {
  echo "FAIL: the pinned bundle carries no templates/ directory."
  echo "      $BUNDLE_URL"
  echo "      Cut a templates-<version> tag, then point the 'sourcery'"
  echo "      binaryTarget at the bundle that tag publishes."
  exit 1
}

if diff -r "$PINNED_TEMPLATES" "$GIT_ROOT/templates" > "$WORK/diff.txt" 2>&1; then
  echo "── ok ── the pinned bundle's templates/ is this commit's templates/"
  rm -rf "$WORK/unpacked" "$ZIP"
  exit 0
fi

echo "FAIL: the pinned bundle's templates/ is not this commit's templates/."
echo ""
sed 's/^/  /' "$WORK/diff.txt"
echo ""
echo "  Cut a templates-<version> tag at this commit, wait for its bundle to"
echo "  publish, then land a commit that changes only the 'sourcery'"
echo "  binaryTarget's url and checksum, and tag the release at that commit."
exit 1
