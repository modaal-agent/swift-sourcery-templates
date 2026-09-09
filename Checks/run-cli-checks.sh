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
#   4. self-scan     an output written INSIDE a scanned root validates: the
#                    generated file is excluded from its own input set, and
#                    a second run over the block-bearing file reproduces it
#                    byte-identically (the fixed point exists).
#   5. config        `validate --template/--args` recomputes the config
#                    description and is green on the pair that generated the
#                    file, red on a different template and red on a different
#                    arg list; passing neither flag keeps the file green.
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

# ── 4. Self-scan ──────────────────────────────────────────────────
# The output lands inside the scanned root. Without the exclusion the
# recorded self-hash predates the write and the file can never validate.
echo ""
echo "── self-scan ──"
SELF_OUT="$FIXTURES/Generated.swift"
"${GENERATE[@]}" --output "$SELF_OUT"
if "$CLI" validate --file "$SELF_OUT" --root "$GIT_ROOT" --sources "$FIXTURES" \
    --expect-bundle 0.0.0-check > /dev/null; then
  echo "  output inside its own root validates"
else
  fail "self-scanned output does not validate — the exclusion is broken"
fi
if grep -q "input:.*Generated.swift" "$SELF_OUT"; then
  fail "the fingerprint lists the output as its own input"
else
  echo "  the block does not list the output as an input"
fi
cp "$SELF_OUT" "$WORK_DIR/self-first.swift"
"${GENERATE[@]}" --output "$SELF_OUT"
if cmp -s "$SELF_OUT" "$WORK_DIR/self-first.swift"; then
  echo "  a second in-place run reproduces the file byte-identically"
else
  fail "the self-scan fixed point does not hold across runs"
fi
rm -f "$SELF_OUT"

# ── 5. Config description ─────────────────────────────────────────
# The block's config line records what generated the file. Without the pair
# the caller currently holds, validate can only check that line against its
# own hash; with it, a config that moved and a file that did not is red.
echo ""
echo "── config ──"
"${GENERATE[@]}" --output "$OUT"
if "${VALIDATE[@]}" --template "$GIT_ROOT/templates/Mocks.swifttemplate" \
    --args "import=Combine,import=Foundation" > /dev/null; then
  echo "  the generating template and args validate"
else
  fail "validate rejected the template/args pair that generated the file"
fi
# The basename is what the line records, so a bare name is the same config.
if "${VALIDATE[@]}" --template Mocks.swifttemplate \
    --args "import=Combine,import=Foundation" > /dev/null; then
  echo "  a bare template name is the same config as its path"
else
  fail "the template basename did not match the recorded line"
fi
expect_red "a different template" "${VALIDATE[@]}" \
  --template Component.swifttemplate --args "import=Combine,import=Foundation"
expect_red "a different arg list" "${VALIDATE[@]}" \
  --template Mocks.swifttemplate --args "import=Foundation"
expect_red "no args where the block records some" "${VALIDATE[@]}" \
  --template Mocks.swifttemplate
expect_red "args without a template" "${VALIDATE[@]}" --args "import=Combine,import=Foundation"
if "${VALIDATE[@]}" > /dev/null; then
  echo "  neither flag: the inputs, the body and the tag still verify"
else
  fail "validate without the config flags is red on a current file"
fi

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" != "0" ]; then
  echo "$FAILURES check(s) failed."
  exit 1
fi
echo "All CLI checks passed."
