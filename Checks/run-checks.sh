#!/bin/bash
#
# Template checks — generate mocks from Checks/Fixtures, then hold the result to
# three gates:
#
#   1. snapshot   the generated file matches Checks/Snapshots (record with --record)
#   2. typecheck  it compiles clean under Swift 5 + complete concurrency checking,
#                 and under the Swift 6 language mode — zero warnings, zero errors
#   3. behaviour  it does what a test needs: counts calls, runs handlers, and
#                 delivers values pushed into its subjects
#
# No simulator, no third-party packages: seconds, not minutes. The Quick specs
# in Examples/ExampleProjectSpm cover the RxSwift and RIBs surfaces this cannot.
#
# Usage:
#   Checks/run-checks.sh              # run the gates
#   Checks/run-checks.sh --record     # rewrite the snapshot, then run the gates
#
# Sourcery: set SOURCERY=/path/to/sourcery to use your own build. Otherwise the
# pinned artifact bundle is downloaded once into .build/.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURES_DIR="$SCRIPT_DIR/Fixtures"
BEHAVIOUR_DIR="$SCRIPT_DIR/Behaviour"
SNAPSHOT_FILE="$SCRIPT_DIR/Snapshots/Mocks.generated.swift"
WORK_DIR="$GIT_ROOT/.build/checks"
GENERATED_FILE="$WORK_DIR/Mocks.generated.swift"

# Keep in step with Package.swift's binary target.
SOURCERY_VERSION="2.3.0"
SOURCERY_URL="https://github.com/krzysztofzablocki/Sourcery/releases/download/${SOURCERY_VERSION}/sourcery-${SOURCERY_VERSION}.artifactbundle.zip"

RECORD=0
[ "$1" = "--record" ] && RECORD=1

mkdir -p "$WORK_DIR" "$(dirname "$SNAPSHOT_FILE")"

# ── Sourcery ──────────────────────────────────────────────────────
if [ -z "$SOURCERY" ]; then
  BUNDLE_DIR="$GIT_ROOT/.build/sourcery-${SOURCERY_VERSION}"
  SOURCERY="$BUNDLE_DIR/sourcery-${SOURCERY_VERSION}.artifactbundle/sourcery/bin/sourcery"
  if [ ! -x "$SOURCERY" ]; then
    echo "Downloading Sourcery ${SOURCERY_VERSION}..."
    mkdir -p "$BUNDLE_DIR"
    curl -sSL -o "$BUNDLE_DIR/sourcery.zip" "$SOURCERY_URL"
    unzip -q -o "$BUNDLE_DIR/sourcery.zip" -d "$BUNDLE_DIR"
    # Some releases nest the executable one level deeper.
    [ -x "$SOURCERY" ] || SOURCERY="$(find "$BUNDLE_DIR" -type f -name sourcery -perm +111 | head -1)"
  fi
fi
[ -x "$SOURCERY" ] || { echo "FAIL: no sourcery executable at '$SOURCERY'"; exit 1; }
echo "Sourcery: $("$SOURCERY" --version)"

# ── 0. Generate ───────────────────────────────────────────────────
echo ""
echo "── generating ──"
"$SOURCERY" \
  --sources "$FIXTURES_DIR" \
  --templates "$GIT_ROOT/templates/Mocks.swifttemplate" \
  --output "$GENERATED_FILE" \
  --args "import=Combine,import=Foundation" \
  --disableCache \
  --quiet
[ -s "$GENERATED_FILE" ] || { echo "FAIL: sourcery produced no output"; exit 1; }
echo "  $(grep -c '^final class .*Mock' "$GENERATED_FILE") mocks generated"

FAILURES=0
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# ── 1. Snapshot ───────────────────────────────────────────────────
echo ""
echo "── snapshot ──"
if [ "$RECORD" = "1" ]; then
  cp "$GENERATED_FILE" "$SNAPSHOT_FILE"
  echo "  recorded $SNAPSHOT_FILE"
elif [ ! -f "$SNAPSHOT_FILE" ]; then
  fail "no snapshot at $SNAPSHOT_FILE — run with --record"
elif diff -u "$SNAPSHOT_FILE" "$GENERATED_FILE" > "$WORK_DIR/snapshot.diff"; then
  echo "  matches"
else
  head -60 "$WORK_DIR/snapshot.diff"
  fail "generated output differs from the snapshot (review, then --record)"
fi

# ── 2. Typecheck, both language modes ─────────────────────────────
typecheck() {
  local label="$1"; shift
  local log="$WORK_DIR/typecheck-$label.log"
  set +e
  xcrun swiftc -typecheck "$@" "$FIXTURES_DIR"/*.swift "$GENERATED_FILE" > "$log" 2>&1
  local status=$?
  set -e
  local diagnostics
  diagnostics=$(grep -cE "^.*: (error|warning): " "$log" || true)
  if [ "$status" != "0" ] || [ "$diagnostics" != "0" ]; then
    grep -E "^.*: (error|warning): " "$log" | head -20
    fail "$label: $diagnostics diagnostics (exit $status)"
  else
    echo "  $label: clean"
  fi
}

echo ""
echo "── typecheck ──"
typecheck "swift5-complete" -swift-version 5 -strict-concurrency=complete
typecheck "swift6" -swift-version 6

# ── 3. Behaviour ──────────────────────────────────────────────────
echo ""
echo "── behaviour ──"
BEHAVIOUR_BIN="$WORK_DIR/behaviour"
if xcrun swiftc -swift-version 6 -o "$BEHAVIOUR_BIN" \
    "$FIXTURES_DIR"/*.swift "$GENERATED_FILE" "$BEHAVIOUR_DIR"/*.swift \
    > "$WORK_DIR/behaviour-build.log" 2>&1; then
  if "$BEHAVIOUR_BIN"; then
    echo "  passed"
  else
    fail "behaviour checks reported failures"
  fi
else
  tail -30 "$WORK_DIR/behaviour-build.log"
  fail "behaviour harness did not build"
fi

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" = "0" ]; then
  echo "ALL CHECKS PASSED"
else
  echo "$FAILURES CHECK(S) FAILED"
  exit 1
fi
