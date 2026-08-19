#!/bin/bash
#
# Template checks — run every template over Checks/Fixtures, then hold the
# results to three gates:
#
#   1. snapshot   each generated file matches Checks/Snapshots (record with --record)
#   2. zero-match each template still WRITES its file over sources with no
#                 matching annotation (the engine skips whitespace-only
#                 renders, so the generators emit a marker comment), and the
#                 result matches its snapshot
#   3. typecheck  they compile clean together under Swift 5 + complete
#                 concurrency checking, and under the Swift 6 language mode —
#                 zero warnings, zero errors
#   4. behaviour  they do what a consumer needs: mocks count calls, run handlers
#                 and deliver values pushed into their subjects; Components
#                 forward to the parent and hold what the level owns
#
# Two templates, one fixture set, one typecheck: a mock and a Component of the
# same protocol have to agree about which member is `nonisolated` and which class
# carries a global actor, and compiling them together is what checks that.
#
# No simulator, no third-party packages: seconds, not minutes. The Quick specs
# in Examples/ExampleProjectSpm cover the RxSwift and RIBs surfaces this cannot.
#
# Usage:
#   Checks/run-checks.sh              # run the gates
#   Checks/run-checks.sh --record     # rewrite the snapshots, then run the gates
#
# Sourcery: set SOURCERY=/path/to/sourcery to use your own build. Otherwise the
# pinned artifact bundle is downloaded once into .build/.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURES_DIR="$SCRIPT_DIR/Fixtures"
BEHAVIOUR_DIR="$SCRIPT_DIR/Behaviour"
SNAPSHOTS_DIR="$SCRIPT_DIR/Snapshots"
WORK_DIR="$GIT_ROOT/.build/checks"

# One entry per template: <output file name>:<template>. Each is generated over
# the same fixtures and snapshotted separately.
TEMPLATES=(
  "Mocks.generated.swift:Mocks.swifttemplate"
  "Components.generated.swift:Component.swifttemplate"
)

RECORD=0
[ "$1" = "--record" ] && RECORD=1

mkdir -p "$WORK_DIR" "$SNAPSHOTS_DIR"

# ── Sourcery ──────────────────────────────────────────────────────
. "$SCRIPT_DIR/ensure-sourcery.sh"

# ── 0. Generate ───────────────────────────────────────────────────
echo ""
echo "── generating ──"
GENERATED_FILES=()
for entry in "${TEMPLATES[@]}"; do
  output_name="${entry%%:*}"
  template="${entry##*:}"
  generated="$WORK_DIR/$output_name"
  "$SOURCERY" \
    --sources "$FIXTURES_DIR" \
    --templates "$GIT_ROOT/templates/$template" \
    --output "$generated" \
    --args "import=Combine,import=Foundation" \
    --disableCache \
    --quiet
  [ -s "$generated" ] || { echo "FAIL: $template produced no output"; exit 1; }
  GENERATED_FILES+=("$generated")
  echo "  $template → $(grep -cE '^(final )?class ' "$generated") types"
done

FAILURES=0
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# ── 1. Snapshot ───────────────────────────────────────────────────
echo ""
echo "── snapshot ──"
for entry in "${TEMPLATES[@]}"; do
  output_name="${entry%%:*}"
  generated="$WORK_DIR/$output_name"
  snapshot="$SNAPSHOTS_DIR/$output_name"
  if [ "$RECORD" = "1" ]; then
    cp "$generated" "$snapshot"
    echo "  recorded $output_name"
  elif [ ! -f "$snapshot" ]; then
    fail "no snapshot at $snapshot — run with --record"
  elif diff -u "$snapshot" "$generated" > "$WORK_DIR/$output_name.diff"; then
    echo "  $output_name: matches"
  else
    head -60 "$WORK_DIR/$output_name.diff"
    fail "$output_name differs from the snapshot (review, then --record)"
  fi
done

# ── 2. Zero-match ─────────────────────────────────────────────────
# A scan that matches nothing must still write the file: consumers commit the
# generated output and fingerprint it, so a pre-registered output has to exist
# before its first annotation. The engine skips whitespace-only renders — the
# marker comment the generators emit on an empty match set is what keeps the
# write happening. Snapshotted like the real outputs.
echo ""
echo "── zero-match ──"
ZERO_MATCH_DIR="$WORK_DIR/zero-match-fixtures"
mkdir -p "$ZERO_MATCH_DIR"
cat > "$ZERO_MATCH_DIR/Unannotated.swift" <<'SWIFT'
// No annotation on purpose: neither template matches this protocol.
public protocol ZeroMatchUnannotated: AnyObject {
    var flag: Bool { get }
}
SWIFT
for entry in "${TEMPLATES[@]}"; do
  output_name="ZeroMatch-${entry%%:*}"
  template="${entry##*:}"
  generated="$WORK_DIR/$output_name"
  rm -f "$generated"
  "$SOURCERY" \
    --sources "$ZERO_MATCH_DIR" \
    --templates "$GIT_ROOT/templates/$template" \
    --output "$generated" \
    --args "import=Combine,import=Foundation" \
    --disableCache \
    --quiet
  if [ ! -s "$generated" ]; then
    fail "$template wrote no output for a zero-match scan"
    continue
  fi
  snapshot="$SNAPSHOTS_DIR/$output_name"
  if [ "$RECORD" = "1" ]; then
    cp "$generated" "$snapshot"
    echo "  recorded $output_name"
  elif [ ! -f "$snapshot" ]; then
    fail "no snapshot at $snapshot — run with --record"
  elif diff -u "$snapshot" "$generated" > "$WORK_DIR/$output_name.diff"; then
    echo "  $output_name: written, matches"
  else
    head -20 "$WORK_DIR/$output_name.diff"
    fail "$output_name differs from the snapshot (review, then --record)"
  fi
done

# ── 3. Typecheck, both language modes ─────────────────────────────
typecheck() {
  local label="$1"; shift
  local log="$WORK_DIR/typecheck-$label.log"
  set +e
  xcrun swiftc -typecheck "$@" "$FIXTURES_DIR"/*.swift "${GENERATED_FILES[@]}" > "$log" 2>&1
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

# ── 4. Behaviour ──────────────────────────────────────────────────
echo ""
echo "── behaviour ──"
BEHAVIOUR_BIN="$WORK_DIR/behaviour"
if xcrun swiftc -swift-version 6 -o "$BEHAVIOUR_BIN" \
    "$FIXTURES_DIR"/*.swift "${GENERATED_FILES[@]}" "$BEHAVIOUR_DIR"/*.swift \
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
