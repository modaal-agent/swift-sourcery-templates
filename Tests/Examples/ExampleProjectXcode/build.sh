#!/bin/bash
#
# Builds the by-URL example and reports which version of this package it
# resolved. Run it after a release publishes — CONTRIBUTING's release procedure
# names this step (specs/001-plugin-source-discovery/followup-xcode-lane.md,
# F9) — and record the version it prints in the release's notes.
#
# It is not a CI lane on purpose: it resolves the package from its published URL
# at a tag, so wiring it into ci.yml would make every branch depend on the last
# published artifact. Everything under Tests/Checks reaches this repository by
# path instead, and that is what keeps a branch's lanes gating the working tree.
#
# Needs Xcode, `xcodegen` (`brew install xcodegen`) and the network. No
# simulator. The `.xcodeproj` is generated and not committed.
#
# Usage:
#   Tests/Examples/ExampleProjectXcode/build.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WORK_DIR="$GIT_ROOT/.build/example-xcode"
DD="$WORK_DIR/DD"

if ! command -v xcodegen > /dev/null; then
  echo "xcodegen is not installed, and this project is generated with it."
  echo "  brew install xcodegen"
  exit 1
fi

echo "── generate ──"
xcodegen generate --spec "$SCRIPT_DIR/xcodegen.yml" --project "$SCRIPT_DIR" -q

echo "── build ──"
LOG="$WORK_DIR/build.log"
mkdir -p "$WORK_DIR"
if ! xcodebuild build \
  -project "$SCRIPT_DIR/ExampleProjectXcode.xcodeproj" \
  -scheme Example \
  -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  -clonedSourcePackagesDirPath "$WORK_DIR/SourcePackages" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  > "$LOG" 2>&1; then
  grep -E 'error:|warning:' "$LOG" | head -20
  echo "FAIL: the example did not build. Full log: $LOG"
  echo "      This project needs the first release after 0.7.0: the plugin has"
  echo "      to supply sources: and output: for a config this short, and to"
  echo "      resolve a bare template name with no package graph to walk."
  exit 1
fi

# What it resolved, which is the thing to record: the pin is `from:`, so the
# version moves on its own as releases publish.
RESOLVED="$SCRIPT_DIR/ExampleProjectXcode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
VERSION="$(python3 -c '
import json, sys
state = json.load(open(sys.argv[1]))
for pin in state.get("pins", []):
    if "swift-sourcery-templates" in pin.get("location", ""):
        print(pin["state"].get("version") or pin["state"].get("revision", "?"))
        break
' "$RESOLVED" 2>/dev/null || echo "?")"

MOCK="$(find "$DD/Build/Intermediates.noindex/BuildToolPluginIntermediates" \
  -path "*/Example/*/.generatedFiles/*/Mocks.generated.swift" -type f 2>/dev/null | head -1)"
if [ -z "$MOCK" ] || ! grep -q 'func upload' "$MOCK"; then
  echo "FAIL: the build succeeded but no mock carrying 'func upload' was generated"
  exit 1
fi

echo ""
echo "BUILT against swift-sourcery-templates $VERSION"
echo "  bare template name resolved, mock at $MOCK"
