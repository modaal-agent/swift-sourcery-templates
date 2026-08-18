#!/bin/bash
#
# CLI checks — build the mock-templates executable and hold it to its gates:
#
#   1. transparency  `generate` over Checks/Fixtures produces, below the
#                    fingerprint block, exactly the bytes run-checks.sh
#                    snapshots: the wrapper adds provenance and changes
#                    nothing else. Two runs produce identical files.
#   2. validation    `validate` proves the file current with no Sourcery
#                    involved, and each staleness class turns it red: a
#                    mutated input, an unlisted new file, a hand-edited
#                    body, a wrong bundle tag.
#   3. imprint       re-imprinting after a body edit records the new body,
#                    and validate is green again.
#
# Usage:
#   Checks/run-cli-checks.sh
#
# Sourcery: set SOURCERY=/path/to/sourcery to use your own build. Otherwise the
# pinned artifact bundle is downloaded once into .build/.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WORK_DIR="$GIT_ROOT/.build/cli-checks"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

FAILURES=0
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# ── Build ─────────────────────────────────────────────────────────
echo "── build ──"
swift build --package-path "$GIT_ROOT" --product mock-templates
CLI="$GIT_ROOT/.build/debug/mock-templates"
[ -x "$CLI" ] || { echo "FAIL: no executable at $CLI"; exit 1; }

# ── Sourcery ──────────────────────────────────────────────────────
. "$SCRIPT_DIR/ensure-sourcery.sh"

# The fixtures are copied so the staleness controls mutate the copy, never
# the tree.
FIXTURES="$WORK_DIR/fixtures"
cp -R "$SCRIPT_DIR/Fixtures" "$FIXTURES"

OUT="$WORK_DIR/Mocks.generated.swift"
GENERATE=(
  "$CLI" generate
  --sourcery "$SOURCERY"
  --templates "$GIT_ROOT/templates/Mocks.swifttemplate"
  --sources "$FIXTURES"
  --args "import=Combine,import=Foundation"
  --bundle-version 0.0.0-check
  --root "$GIT_ROOT"
  --disable-cache
)
IMPRINT=(
  "$CLI" imprint
  --templates "$GIT_ROOT/templates/Mocks.swifttemplate"
  --sources "$FIXTURES"
  --args "import=Combine,import=Foundation"
  --bundle-version 0.0.0-check
  --root "$GIT_ROOT"
  --output "$OUT"
)
VALIDATE=(
  "$CLI" validate
  --file "$OUT"
  --root "$GIT_ROOT"
  --sources "$FIXTURES"
  --expect-bundle 0.0.0-check
)

strip_block() {  # <file> <dest> — the bytes below the fingerprint block
  python3 - "$1" "$2" <<'EOF'
import sys
data = open(sys.argv[1], "rb").read()
marker = b"\n// mock-templates:end\n"
index = data.find(marker)
assert index >= 0, "no fingerprint end marker"
open(sys.argv[2], "wb").write(data[index + len(marker):])
EOF
}

# ── 1. Transparency ───────────────────────────────────────────────
echo ""
echo "── transparency ──"
"${GENERATE[@]}" --output "$OUT"
strip_block "$OUT" "$WORK_DIR/body.swift"
if diff -q "$SCRIPT_DIR/Snapshots/Mocks.generated.swift" "$WORK_DIR/body.swift" > /dev/null; then
  echo "  body matches the snapshot"
else
  fail "the body below the block differs from Snapshots/Mocks.generated.swift"
fi

"${GENERATE[@]}" --output "$WORK_DIR/second.swift"
if cmp -s "$OUT" "$WORK_DIR/second.swift"; then
  echo "  two runs are byte-identical"
else
  fail "two generate runs differ — the fingerprint is not deterministic"
fi

# ── 2. Validation ─────────────────────────────────────────────────
echo ""
echo "── validation ──"
if "${VALIDATE[@]}" > /dev/null; then
  echo "  current file validates (no Sourcery on the validate path)"
else
  fail "validate rejected a file generate just wrote"
fi

expect_red() {  # <label> <command...>
  local label="$1"; shift
  if "$@" > /dev/null 2>&1; then
    fail "$label went green — it must fail"
  else
    echo "  $label: red, as it must be"
  fi
}

echo "// mutation" >> "$FIXTURES/Isolation.swift"
expect_red "mutated input" "${VALIDATE[@]}"
cp "$SCRIPT_DIR/Fixtures/Isolation.swift" "$FIXTURES/Isolation.swift"

echo "enum Unlisted {}" > "$FIXTURES/Unlisted.swift"
expect_red "unlisted new file" "${VALIDATE[@]}"
rm "$FIXTURES/Unlisted.swift"

echo "// hand edit" >> "$OUT"
expect_red "hand-edited body" "${VALIDATE[@]}"

# ── 3. Imprint ────────────────────────────────────────────────────
echo ""
echo "── imprint ──"
"${IMPRINT[@]}"
if "${VALIDATE[@]}" > /dev/null; then
  echo "  re-imprint records the edited body; validate is green again"
else
  fail "validate stayed red after imprint"
fi

expect_red "wrong bundle tag" "$CLI" validate --file "$OUT" --root "$GIT_ROOT" --expect-bundle 9.9.9

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" != "0" ]; then
  echo "$FAILURES check(s) failed."
  exit 1
fi
echo "All CLI checks passed."
