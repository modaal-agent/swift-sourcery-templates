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
#   3. near-miss  a misspelled selector fails generation naming the canonical
#                 spelling; a misspelled option still generates and writes one
#                 comment line
#   4. collision  two members that would carry one name fail generation naming
#                 the protocol and the member, instead of writing a file the
#                 consumer's compiler rejects
#   5. typecheck  they compile clean together under Swift 5 + complete
#                 concurrency checking, and under the Swift 6 language mode —
#                 zero warnings, zero errors
#   6. behaviour  they do what a consumer needs: mocks count calls, run handlers
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
GIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# ── 3. Near miss ──────────────────────────────────────────────────
# Names are matched exactly, including case, and a spelling that differs only in
# case used to be silent: Sourcery stored the key, no template asked for it, and
# generation completed with the mock simply absent. Severity follows what the
# annotation does. A selector that matches nothing means the type generates
# nothing, so it fails the run; an option leaves a working mock missing one
# behaviour, and an adopter may own the name for their own template, so it writes
# a comment into the file and carries on.
#
# The comment rather than a log line is measured, not chosen: a Swift template's
# stdout is the generated file, and Sourcery 2.3.0 turns any write to the
# template's stderr into `error: <template>: <text>` and aborts with exit 3.
echo ""
echo "── near-miss ──"
NEAR_MISS_DIR="$WORK_DIR/near-miss"
rm -rf "$NEAR_MISS_DIR"
mkdir -p "$NEAR_MISS_DIR/selector" "$NEAR_MISS_DIR/option"
cat > "$NEAR_MISS_DIR/selector/Selector.swift" <<'SWIFT'
/// sourcery: protocolmock
public protocol NearMissSelector: AnyObject {
    func run()
}
SWIFT
cat > "$NEAR_MISS_DIR/option/Option.swift" <<'SWIFT'
/// sourcery: ProtocolMock
public protocol NearMissOption: AnyObject {
    /// sourcery: skipargumentrecording
    func run(id: String)
}
SWIFT

near_miss_log="$WORK_DIR/near-miss-selector.log"
if "$SOURCERY" --sources "$NEAR_MISS_DIR/selector" \
     --templates "$GIT_ROOT/templates/Mocks.swifttemplate" \
     --output "$NEAR_MISS_DIR/selector.generated.swift" \
     --disableCache --quiet > "$near_miss_log" 2>&1; then
  fail "a misspelled selector generated instead of failing"
elif grep -q 'protocolmock' "$near_miss_log" \
  && grep -q 'NearMissSelector' "$near_miss_log" \
  && grep -q 'ProtocolMock' "$near_miss_log"; then
  echo "  a misspelled selector fails, naming the type and the canonical spelling"
else
  tail -10 "$near_miss_log"
  fail "a misspelled selector failed, but its message does not name the type, the spelling found and the canonical form"
fi

near_miss_option="$NEAR_MISS_DIR/option.generated.swift"
if ! "$SOURCERY" --sources "$NEAR_MISS_DIR/option" \
       --templates "$GIT_ROOT/templates/Mocks.swifttemplate" \
       --output "$near_miss_option" \
       --disableCache --quiet > "$WORK_DIR/near-miss-option.log" 2>&1; then
  tail -10 "$WORK_DIR/near-miss-option.log"
  fail "a misspelled option failed the run, and it must not"
else
  notes="$(grep -c 'sourcery-templates:' "$near_miss_option" || true)"
  if [ "$notes" != "1" ]; then
    fail "a misspelled option wrote $notes comment lines, expected 1"
  elif ! grep -q 'skipArgumentRecording' "$near_miss_option"; then
    fail "the comment does not name the canonical spelling"
  elif ! grep -q 'class NearMissOptionMock' "$near_miss_option"; then
    fail "a misspelled option stopped the mock being generated"
  else
    echo "  a misspelled option writes one comment line and still generates"
  fi
fi

# ── 4. Collision ──────────────────────────────────────────────────
# Each case here fails generation on purpose, so none of it can live in
# Fixtures/ — one fixture that fails takes the whole lane's generation with it,
# the way the near-miss selector case does. What is checked is that the failure
# names the protocol and the member, rather than the template emitting a file
# whose two identical declarations the consumer's compiler reports instead.
echo ""
echo "── collision ──"
COLLISION_DIR="$WORK_DIR/collision"
rm -rf "$COLLISION_DIR"

# <case>:<protocol>:<member named in the message>
COLLISION_CASES=(
  "bookkeeping:CollidingBookkeeping:draftSetCount"
  "overload:CollidingOverload:sendToVoidCallCount"
)

mkdir -p "$COLLISION_DIR/bookkeeping"
cat > "$COLLISION_DIR/bookkeeping/Bookkeeping.swift" <<'SWIFT'
// A requirement whose name is another requirement's bookkeeping member.
/// sourcery: ProtocolMock
public protocol CollidingBookkeeping: AnyObject {
    var draft: String { get set }
    var draftSetCount: Int { get set }
}
SWIFT

mkdir -p "$COLLISION_DIR/overload"
cat > "$COLLISION_DIR/overload/Overload.swift" <<'SWIFT'
// Two overloads sharing their labels, their parameter count and their return
// type, differing only in a parameter type — which no part of the name derives
// from. The long form and the return-type discriminator both leave them equal,
// which is step 4 of the overload chain.
/// sourcery: ProtocolMock
public protocol CollidingOverload: AnyObject {
    func send(to target: String)
    func send(to target: Int)
}
SWIFT

for entry in "${COLLISION_CASES[@]}"; do
  case_name="${entry%%:*}"
  rest="${entry#*:}"
  protocol_name="${rest%%:*}"
  member_name="${rest##*:}"
  log="$WORK_DIR/collision-$case_name.log"
  if "$SOURCERY" --sources "$COLLISION_DIR/$case_name" \
       --templates "$GIT_ROOT/templates/Mocks.swifttemplate" \
       --output "$COLLISION_DIR/$case_name.generated.swift" \
       --args "import=Combine,import=Foundation" \
       --disableCache --quiet > "$log" 2>&1; then
    fail "$case_name: a colliding member generated instead of failing"
  elif grep -q "$protocol_name" "$log" && grep -q "$member_name" "$log"; then
    echo "  $case_name: fails, naming $protocol_name and $member_name"
  else
    tail -10 "$log"
    fail "$case_name: failed, but the message does not name $protocol_name and $member_name"
  fi
done

# ── 5. Typecheck, both language modes ─────────────────────────────
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

# ── 6. Behaviour ──────────────────────────────────────────────────
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
