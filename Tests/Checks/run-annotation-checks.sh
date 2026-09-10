#!/bin/bash
#
# Annotation registry checks — the two directions of one rule:
#
#   a verb the templates read is declared in the registry   (AC1)
#   a verb the registry declares is read by the templates   (AC3)
#
# plus the shape the renderer's parser depends on, the naming schema, and the
# freshness of every rendered table.
#
# `grep`, `awk` and `diff`. No Swift toolchain, no Sourcery, no network, so this
# runs on ubuntu in seconds, ungated. That is deliberate: a push that edits only
# `README.md` sets `code=false` at `ci.yml:101` and skips all four macOS lanes,
# and a stale rendition is exactly what such a push produces.
#
# Usage:
#   Tests/Checks/run-annotation-checks.sh
#   Tests/Checks/run-annotation-checks.sh --self-test   # each check red on a seeded violation
#
# `--self-test` is the red control the other lanes have: a check that cannot go
# red is not a check. It copies the files this script reads into a temporary
# tree, breaks one thing per check, and asserts that check — and no other — goes
# red. The working tree is never written to.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$GIT_ROOT"

if [ "${1:-}" = "--self-test" ]; then
  # ── Red controls ────────────────────────────────────────────────
  # One mutation per check, applied inside a temporary copy of the files this
  # script reads. Each declares the exact set of checks it must turn red — a
  # set, not a single id, because some checks are downstream of others by
  # construction: any edit to a record's `name`, and any edit inside a rendered
  # block, makes AC6 red as well, and that is the design rather than a leak.
  SELF_TEST_DIR="$(mktemp -d)"
  trap 'rm -rf "$SELF_TEST_DIR"' EXIT
  seed_failures=0
  R=templates/Annotations/AnnotationRegistry.swift

  # Replace one exact line with the contents of a file.
  splice_line() {
    awk -v target="$2" -v blockfile="$3" '
      $0 == target { while ((getline line < blockfile) > 0) print line; next }
      { print }
    ' "$1" > "$1.seeded" && mv "$1.seeded" "$1"
  }

  # AC1 — a template names a verb directly.
  mutate_AC1() { printf '\n// let seeded = annotations["Foo"]\n' >> templates/Mocks/MockGenerator.swift; }

  # AC2 — a record is declared and not listed in `all`.
  mutate_AC2() { sed -i.bak '/^        owns,$/d' "$R" && rm -f "$R.bak"; }

  # AC3 — a record no template reads. Renaming the identifier rather than adding
  # a record leaves the rendered table identical, so this control isolates AC3.
  mutate_AC3() {
    sed -i.bak 's/^    static let owns = Annotation($/    static let ownsUnread = Annotation(/' "$R"
    sed -i.bak 's/^        owns,$/        ownsUnread,/' "$R"
    rm -f "$R.bak"
  }

  # AC4 — a live name is also retired.
  mutate_AC4() {
    cat > "$SELF_TEST_DIR/retired.txt" <<'RETIRED'
    static let retired: [RetiredAnnotation] = [
        RetiredAnnotation(
            name: "owns",
            aliases: [],
            kind: .option,
            retiredIn: "0.0.0",
            replacement: "nothing"
        ),
    ]
RETIRED
    splice_line "$R" "    static let retired: [RetiredAnnotation] = []" "$SELF_TEST_DIR/retired.txt"
  }

  # AC5 — a field the parser cannot read.
  mutate_AC5() { sed -i.bak 's/^        kind: .option,$/        kind: option,/' "$R" && rm -f "$R.bak"; }

  # AC6 — a rendered block edited by hand.
  mutate_AC6() { sed -i.bak 's/^| `owns` | Protocol |/| `owns` | Protocols |/' README.md && rm -f README.md.bak; }

  # AC7 — a selector spelled as an option.
  mutate_AC7() { sed -i.bak 's/^        name: "ProtocolMock",$/        name: "protocolMock",/' "$R" && rm -f "$R.bak"; }

  # AC8 — an alias documented inside a rendered block.
  mutate_AC8() { sed -i.bak 's/^| `ProtocolMock` |/| `ProtocolMock` (was `CreateMock`) |/' README.md && rm -f README.md.bak; }

  # AC9 — an entry point that filters without scanning first.
  mutate_AC9() { sed -i.bak '/rejectNearMisses/d' templates/Component.swifttemplate && rm -f templates/Component.swifttemplate.bak; }

  seed() {
    local check="$1" expected="$2"
    local root="$SELF_TEST_DIR/$check"
    mkdir -p "$root/Tests/Checks"
    cp -R templates "$root/templates"
    cp -R Scripts "$root/Scripts"
    cp README.md "$root/README.md"
    cp -R skills "$root/skills"
    cp "$SCRIPT_DIR/run-annotation-checks.sh" "$root/Tests/Checks/"
    if ! ( cd "$root" && "mutate_$check" ); then
      echo "  $check: FAIL — the mutation itself did not apply"
      seed_failures=$((seed_failures + 1))
      return
    fi
    local out reds
    out="$("$root/Tests/Checks/run-annotation-checks.sh" 2>&1)"
    reds="$(printf '%s\n' "$out" | grep -oE '^  AC[0-9]+: FAIL' | grep -oE 'AC[0-9]+' | sort -u | tr '\n' ' ')"
    reds="${reds% }"
    if [ "$reds" = "$expected" ]; then
      echo "  $check: red as it must be — $reds"
    else
      echo "  $check: FAIL — expected '$expected' red, got '${reds:-nothing}'"
      printf '%s\n' "$out" | sed 's/^/      /'
      seed_failures=$((seed_failures + 1))
    fi
  }

  echo ""
  echo "── red controls ──"
  seed AC1 "AC1"
  seed AC2 "AC2"
  seed AC3 "AC3"
  seed AC4 "AC4"
  seed AC5 "AC5"
  seed AC6 "AC6"
  seed AC7 "AC6 AC7"
  seed AC8 "AC6 AC8"
  seed AC9 "AC9"

  echo ""
  if [ "$seed_failures" = "0" ]; then
    echo "ALL RED CONTROLS PASSED"
    exit 0
  fi
  echo "$seed_failures RED CONTROL(S) FAILED"
  exit 1
fi

REGISTRY="templates/Annotations/AnnotationRegistry.swift"
RENDER="Scripts/render-annotations.sh"
RENDER_TARGETS=(
  README.md
  skills/swift-sourcery-mocks/SKILL.md
  skills/swift-sourcery-mocks/references/writing-testable-protocols.md
)

START='<!-- annotations:start -->'
END='<!-- annotations:end -->'

FAILURES=0
pass() { echo "  $1: ok — $2"; }
fail() { echo "  $1: FAIL — $2"; FAILURES=$((FAILURES + 1)); }

[ -f "$REGISTRY" ] || { echo "FAIL: no registry at $REGISTRY"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$RENDER" --dump > "$TMP/records" || { echo "FAIL: $RENDER --dump"; exit 1; }
"$RENDER" --dump-retired > "$TMP/retired" || { echo "FAIL: $RENDER --dump-retired"; exit 1; }

# Files that read annotations, and the entry points among them. `_header` is
# included by every entry point rather than being one.
TEMPLATE_FILES="$(find templates -type f \( -name '*.swift' -o -name '*.swifttemplate' \) | grep -v '^templates/Annotations/' | sort)"
ENTRY_POINTS="$(find templates -maxdepth 1 -type f -name '*.swifttemplate' | grep -v '/_' | sort)"

echo ""
echo "── registry ──"
echo "  $(wc -l < "$TMP/records" | tr -d ' ') records, $(wc -l < "$TMP/retired" | tr -d ' ') retired, $(printf '%s\n' "$ENTRY_POINTS" | wc -l | tr -d ' ') entry points"

# ── AC1: no string-literal annotation read outside templates/Annotations/ ──
echo ""
echo "── AC1: every annotation verb is named in the registry ──"
LITERALS="$(printf '%s\n' "$TEMPLATE_FILES" | xargs grep -nE 'annotations\[[^]]*"|annotations\(for: *\[? *"' 2>/dev/null)"
if [ -z "$LITERALS" ]; then
  pass AC1 "no string-literal annotation read outside templates/Annotations/"
else
  fail AC1 "a template names a verb directly instead of asking for a record:"
  printf '%s\n' "$LITERALS" | sed 's/^/      /'
fi

# ── AC5: the record shape the renderer's parser depends on ──
# Runs before the checks that read the parse, because a record the parser skips
# would make every one of them pass by not being seen.
echo ""
echo "── AC5: every record matches the parser's contract ──"
SHAPE="$(awk '
  BEGIN { split("name aliases kind target effect valueHint matching", expected, " ") }
  /^    static let [a-zA-Z]+ = Annotation\($/ { inrecord = 1; ident = $3; field = 0; next }
  inrecord && /^    \)$/ {
    if (field < 6) printf "%s:%d: %s carries %d fields, expected at least 6\n", FILENAME, NR, ident, field
    inrecord = 0; next
  }
  inrecord {
    field++
    if (field > 7) { printf "%s:%d: %s carries more than 7 fields\n", FILENAME, NR, ident; next }
    key = expected[field]
    pattern = "^        " key ": "
    if ($0 !~ pattern) { printf "%s:%d: %s expected field %d to be `%s`, got: %s\n", FILENAME, NR, ident, field, key, $0; next }
    value = $0; sub(/^        [a-zA-Z]+: /, "", value); sub(/,$/, "", value)
    ok = 0
    if (key == "name" || key == "target" || key == "effect") ok = (value ~ /^"[^"]*"$/)
    else if (key == "aliases") ok = (value ~ /^\[("[^"]*"(, )?)*\]$/)
    else if (key == "kind") ok = (value == ".templateSelector" || value == ".option")
    else if (key == "valueHint") ok = (value == "nil" || value ~ /^"[^"]*"$/)
    else if (key == "matching") ok = (value == ".exact" || value == ".caseInsensitive")
    if (!ok) printf "%s:%d: %s field `%s` does not match its pattern: %s\n", FILENAME, NR, ident, key, value
  }
  END { if (inrecord) printf "%s: a record is not closed by `    )`\n", FILENAME }
' "$REGISTRY")"
OPENERS="$(grep -cE '(^|[^A-Za-z])Annotation\(' "$REGISTRY")"
PARSED="$(wc -l < "$TMP/records" | tr -d ' ')"
RETIRED_OPENERS="$(grep -cE 'RetiredAnnotation\(' "$REGISTRY")"
if [ -n "$SHAPE" ]; then
  fail AC5 "a record does not match the field patterns:"
  printf '%s\n' "$SHAPE" | sed 's/^/      /'
elif [ "$OPENERS" != "$PARSED" ]; then
  fail AC5 "$OPENERS occurrences of \`Annotation(\`, $PARSED records parsed — the parser skipped one"
else
  pass AC5 "$PARSED records, $RETIRED_OPENERS retired, every field line matches its pattern"
fi

# ── AC2: every declared record is listed in `all` ──
echo ""
echo "── AC2: every record is listed in \`all\` ──"
awk '/^    static let ([a-zA-Z]+) = Annotation\($/ { print $3 }' "$REGISTRY" | sort > "$TMP/declared"
awk '/^    static let all: \[Annotation\] = \[$/ { inlist = 1; next }
     inlist && /^    \]$/ { inlist = 0 }
     inlist { gsub(/[ ,]/, ""); if ($0 != "") print }' "$REGISTRY" | sort > "$TMP/listed"
MISSING="$(comm -23 "$TMP/declared" "$TMP/listed")"
EXTRA="$(comm -13 "$TMP/declared" "$TMP/listed")"
if [ -n "$MISSING" ]; then
  fail AC2 "declared and not in \`all\`, so the near-miss scan never sees it: $(printf '%s' "$MISSING" | tr '\n' ' ')"
elif [ -n "$EXTRA" ]; then
  fail AC2 "listed in \`all\` and not declared: $(printf '%s' "$EXTRA" | tr '\n' ' ')"
else
  pass AC2 "$(wc -l < "$TMP/listed" | tr -d ' ') records declared, all of them listed"
fi

# ── Which records each file reads ────────────────────────────────
# A record is read by a file when the file writes `AnnotationRegistry.<ident>`,
# or writes a composite the registry declares — `mockSelectors` — whose members
# it then is. `all` does not count: it is the near-miss scan's input, not a read.
composite_members() {
  awk -v name="$1" '
    $0 ~ ("^    static let " name ": \\[Annotation\\] = \\[") { inlist = 1 }
    inlist {
      line = $0
      sub(/^.*= \[/, "", line)
      sub(/\].*$/, "", line)
      gsub(/[ ]/, "", line)
      n = split(line, parts, ",")
      for (i = 1; i <= n; i++) if (parts[i] != "") print parts[i]
      if ($0 ~ /\]/) inlist = 0
    }
  ' "$REGISTRY"
}
COMPOSITES="$(awk '/^    static let [a-zA-Z]+: \[Annotation\] = \[/ { ident = $3; sub(/:$/, "", ident); if (ident != "all:") print ident }' "$REGISTRY" | sed 's/:$//')"

reads_of() {  # reads_of <files...> → identifiers, one per line
  local refs
  refs="$(grep -ohE 'AnnotationRegistry\.[a-zA-Z]+' "$@" 2>/dev/null | sed 's/^AnnotationRegistry\.//' | sort -u)"
  local out="$refs"
  local c
  for c in $COMPOSITES; do
    if printf '%s\n' "$refs" | grep -qx "$c"; then
      out="$out
$(composite_members "$c")"
    fi
  done
  printf '%s\n' "$out" | grep -v '^$' | sort -u
}

# ── AC3: every record is read by a template ──
echo ""
echo "── AC3: every record in \`all\` is read by a template ──"
# shellcheck disable=SC2086
reads_of $TEMPLATE_FILES > "$TMP/read"
ORPHANS="$(comm -23 "$TMP/listed" "$TMP/read")"
if [ -n "$ORPHANS" ]; then
  fail AC3 "declared and read by no template — delete it or retire it: $(printf '%s' "$ORPHANS" | tr '\n' ' ')"
else
  pass AC3 "no orphan records"
fi

# ── AC4: no name in both `all` and `retired` ──
echo ""
echo "── AC4: no name is both live and retired ──"
awk -F'\t' '{ print $2; if ($3 != "") { n = split($3, a, ","); for (i = 1; i <= n; i++) print a[i] } }' "$TMP/records" | sort > "$TMP/live-names"
awk -F'\t' '{ print $1; if ($2 != "") { n = split($2, a, ","); for (i = 1; i <= n; i++) print a[i] } }' "$TMP/retired" | sort > "$TMP/retired-names"
BOTH="$(comm -12 "$TMP/live-names" "$TMP/retired-names")"
DUPES="$(uniq -d "$TMP/live-names")"
if [ -n "$BOTH" ]; then
  fail AC4 "a retired verb was re-added under its old name: $(printf '%s' "$BOTH" | tr '\n' ' ')"
elif [ -n "$DUPES" ]; then
  fail AC4 "one spelling is claimed by two records: $(printf '%s' "$DUPES" | tr '\n' ' ')"
else
  pass AC4 "$(wc -l < "$TMP/live-names" | tr -d ' ') spellings, each claimed once"
fi

# ── AC7: the naming schema, and selector reachability ──
echo ""
echo "── AC7: selectors are UpperCamelCase nouns, options lowerCamelCase ──"
SCHEMA="$(awk -F'\t' '
  {
    kind = $4
    pattern = (kind == "templateSelector") ? "^[A-Z][A-Za-z]*$" : "^[a-z][A-Za-z]*$"
    if ($2 !~ pattern) printf "%s: name `%s` does not match %s for a %s\n", $1, $2, pattern, kind
    if ($3 != "") {
      n = split($3, a, ",")
      for (i = 1; i <= n; i++) if (a[i] !~ pattern) printf "%s: alias `%s` does not match %s for a %s\n", $1, a[i], pattern, kind
    }
  }
' "$TMP/records")"
awk -F'\t' '$4 == "templateSelector" { print $1 }' "$TMP/records" | sort > "$TMP/selectors"
UNREACHED=""
NO_SELECTOR=""
for entry in $ENTRY_POINTS; do
  reads_of "$entry" > "$TMP/entry-reads"
  if [ -z "$(comm -12 "$TMP/selectors" "$TMP/entry-reads")" ]; then
    NO_SELECTOR="$NO_SELECTOR $entry"
  fi
done
# shellcheck disable=SC2086
reads_of $ENTRY_POINTS > "$TMP/entry-reads-all"
UNREACHED="$(comm -23 "$TMP/selectors" "$TMP/entry-reads-all" | tr '\n' ' ')"
if [ -n "$SCHEMA" ]; then
  fail AC7 "the naming schema is broken:"
  printf '%s\n' "$SCHEMA" | sed 's/^/      /'
elif [ -n "${UNREACHED// /}" ]; then
  fail AC7 "a selector no entry point filters on:$UNREACHED"
elif [ -n "$NO_SELECTOR" ]; then
  fail AC7 "an entry point that filters on no selector:$NO_SELECTOR"
else
  pass AC7 "$(wc -l < "$TMP/selectors" | tr -d ' ') selectors, each read by an entry point; every entry point reads one"
fi

# ── AC6: every rendered block is current ──
echo ""
echo "── AC6: every rendered block is current ──"
if RENDERED="$("$RENDER" 2>&1)"; then
  pass AC6 "$(printf '%s' "$RENDERED" | tr -d ' ' | tr '\n' ' ')"
else
  fail AC6 "a rendition is stale — run $RENDER --write, read the diff, commit it:"
  printf '%s\n' "$RENDERED" | sed 's/^/      /'
fi

# ── AC8: no alias inside a rendered block ──
echo ""
echo "── AC8: no rendered block names an alias ──"
ALIASES="$(awk -F'\t' '$3 != "" { n = split($3, a, ","); for (i = 1; i <= n; i++) print a[i] }' "$TMP/records" | sort -u)"
DOCUMENTED=""
for target in "${RENDER_TARGETS[@]}"; do
  awk -v s="$START" -v e="$END" '$0 == s { inblock = 1; next } $0 == e { inblock = 0 } inblock' "$target" > "$TMP/block"
  for alias in $ALIASES; do
    if grep -Fwq -- "$alias" "$TMP/block"; then
      DOCUMENTED="$DOCUMENTED $target:$alias"
    fi
  done
done
if [ -n "$DOCUMENTED" ]; then
  fail AC8 "an alias appears inside a rendered block, which makes it a second canonical form:$DOCUMENTED"
else
  pass AC8 "$(printf '%s\n' "$ALIASES" | wc -l | tr -d ' ') aliases, none documented"
fi

# ── AC9: the near-miss scan runs before every filter ──
echo ""
echo "── AC9: every entry point scans before it filters ──"
UNSCANNED=""
for entry in $ENTRY_POINTS; do
  scan="$(grep -n 'AnnotationRegistry\.rejectNearMisses(in: types\.protocols)' "$entry" | head -1 | cut -d: -f1)"
  filter="$(grep -n 'isAnnotated(' "$entry" | head -1 | cut -d: -f1)"
  if [ -z "$scan" ]; then
    UNSCANNED="$UNSCANNED $entry(no scan)"
  elif [ -z "$filter" ]; then
    UNSCANNED="$UNSCANNED $entry(no filter)"
  elif [ "$scan" -ge "$filter" ]; then
    UNSCANNED="$UNSCANNED $entry(scan at :$scan, filter at :$filter)"
  fi
done
if [ -n "$UNSCANNED" ]; then
  fail AC9 "a misspelled selector would be silent — the scan has to run over unfiltered \`types.protocols\` first:$UNSCANNED"
else
  pass AC9 "every entry point scans unfiltered protocols before filtering them"
fi

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" = "0" ]; then
  echo "ALL ANNOTATION CHECKS PASSED"
else
  echo "$FAILURES ANNOTATION CHECK(S) FAILED"
  exit 1
fi
