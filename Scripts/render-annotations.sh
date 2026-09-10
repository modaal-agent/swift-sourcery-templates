#!/bin/bash
#
# Render the annotation registry into every document that documents it.
#
# `templates/Annotations/AnnotationRegistry.swift` is the one place an annotation
# verb is named. This script parses it — with `awk`, not with a Swift compiler —
# and writes a markdown table between `<!-- annotations:start -->` and
# `<!-- annotations:end -->` in each target below.
#
# No toolchain, no Sourcery, no network: a push that edits only `README.md` skips
# every macOS lane, and that is exactly the push whose rendition has to be
# checked. `Tests/Checks/run-annotation-checks.sh` calls this in check mode on
# ubuntu.
#
# Canonical names only. An alias exists so a spelling that once worked keeps
# working; rendering one would make it a second canonical form with no way back.
#
# Usage:
#   Scripts/render-annotations.sh            # check: re-render, diff, non-zero if stale
#   Scripts/render-annotations.sh --write    # rewrite the blocks in place
#   Scripts/render-annotations.sh --print [flat|grouped]
#   Scripts/render-annotations.sh --dump     # the parsed registry as TSV
#   Scripts/render-annotations.sh --dump-retired
#
# This is `run-checks.sh --record`'s discipline applied to prose: run it, read
# the diff it prints, commit what it wrote.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$GIT_ROOT/templates/Annotations/AnnotationRegistry.swift"

START='<!-- annotations:start -->'
END='<!-- annotations:end -->'

# <path relative to the repository root>:<style>. `flat` is one table in registry
# order; `grouped` splits selectors from options.
TARGETS=(
  "README.md:flat"
  "skills/swift-sourcery-mocks/SKILL.md:flat"
  "skills/swift-sourcery-mocks/references/writing-testable-protocols.md:grouped"
)

[ -f "$REGISTRY" ] || { echo "FAIL: no registry at $REGISTRY" >&2; exit 1; }

# ── Parse ─────────────────────────────────────────────────────────
# One TSV line per record: identifier, name, aliases (comma-joined), kind,
# target, effect, valueHint, matching. `matching` is empty once phase A4 deletes
# the field. The record shape this depends on is stated in the registry's own
# header comment and asserted by check AC5.
dump() {
  awk '
    function unquote(v) {
      sub(/,$/, "", v)
      if (v == "nil") return ""
      sub(/^"/, "", v); sub(/"$/, "", v)
      return v
    }
    /^    static let [a-zA-Z]+ = Annotation\($/ {
      ident = $3
      name = ""; aliases = ""; kind = ""; target = ""; effect = ""; hint = ""; matching = ""
      inrecord = 1
      next
    }
    inrecord && /^    \)$/ {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ident, name, aliases, kind, target, effect, hint, matching
      inrecord = 0
      next
    }
    inrecord {
      line = $0
      sub(/^        /, "", line)
      key = line; sub(/:.*$/, "", key)
      value = line; sub(/^[a-zA-Z]+: /, "", value)
      if (key == "name") name = unquote(value)
      else if (key == "aliases") {
        sub(/,$/, "", value); sub(/^\[/, "", value); sub(/\]$/, "", value)
        gsub(/"/, "", value); gsub(/, /, ",", value)
        aliases = value
      }
      else if (key == "kind") { sub(/,$/, "", value); sub(/^\./, "", value); kind = value }
      else if (key == "target") target = unquote(value)
      else if (key == "effect") effect = unquote(value)
      else if (key == "valueHint") hint = unquote(value)
      else if (key == "matching") { sub(/,$/, "", value); sub(/^\./, "", value); matching = value }
    }
  ' "$REGISTRY"
}

# One TSV line per retired entry: name, aliases (comma-joined), kind, retiredIn,
# replacement. Empty while `retired` is empty, which is its resting state.
dump_retired() {
  awk '
    function unquote(v) {
      sub(/,$/, "", v)
      sub(/^"/, "", v); sub(/"$/, "", v)
      return v
    }
    /^        RetiredAnnotation\($/ {
      name = ""; aliases = ""; kind = ""; retiredin = ""; replacement = ""
      inrecord = 1
      next
    }
    inrecord && /^        \),$/ {
      printf "%s\t%s\t%s\t%s\t%s\n", name, aliases, kind, retiredin, replacement
      inrecord = 0
      next
    }
    inrecord {
      line = $0
      sub(/^            /, "", line)
      key = line; sub(/:.*$/, "", key)
      value = line; sub(/^[a-zA-Z]+: /, "", value)
      if (key == "name") name = unquote(value)
      else if (key == "aliases") {
        sub(/,$/, "", value); sub(/^\[/, "", value); sub(/\]$/, "", value)
        gsub(/"/, "", value); gsub(/, /, ",", value)
        aliases = value
      }
      else if (key == "kind") { sub(/,$/, "", value); sub(/^\./, "", value); kind = value }
      else if (key == "retiredIn") retiredin = unquote(value)
      else if (key == "replacement") replacement = unquote(value)
    }
  ' "$REGISTRY"
}

# ── Render ────────────────────────────────────────────────────────
# Rows are built in awk rather than in a shell `read` loop: tab is IFS
# whitespace, so `read` collapses the empty field a record with no alias or no
# value hint produces, and every column after it shifts left.
#
# The first column carries the name and, where the verb takes one, an example
# value: `subject = "CurrentValue"`.
table() {
  local want_kind="$1"
  printf '| Annotation | Target | Effect |\n'
  printf '|------------|--------|--------|\n'
  dump | awk -F'\t' -v want="$want_kind" '
    want != "" && $4 != want { next }
    $7 != "" { printf "| `%s = \"%s\"` | %s | %s |\n", $2, $7, $5, $6; next }
             { printf "| `%s` | %s | %s |\n", $2, $5, $6 }
  '
}

# One sentence stating how a name is matched. While any record still carries
# `.caseInsensitive` — that is, between phases A1 and A4 — it names the records
# that are matched exactly instead, because the vocabulary is irregular and
# saying otherwise would be false.
matching_sentence() {
  local exact
  exact="$(dump | awk -F'\t' '$8 == "exact" { printf "`%s`\n", $2 }')"
  if [ -z "$(dump | awk -F'\t' '$8 == "caseInsensitive"')" ]; then
    printf 'Annotation names are matched exactly, including case.\n'
    return
  fi
  local list
  list="$(printf '%s\n' "$exact" | paste -sd '@' - | sed 's/@/, /g')"
  # The last separator becomes " and ".
  list="$(printf '%s' "$list" | sed 's/\(.*\), /\1 and /')"
  printf 'Annotation names are matched case-insensitively, except for %s, which are matched exactly, including case.\n' "$list"
}

block() {
  local style="$1"
  printf '%s\n' "$START"
  printf '<!-- Rendered from templates/Annotations/AnnotationRegistry.swift by Scripts/render-annotations.sh. Do not edit inside this block. -->\n'
  printf '\n'
  matching_sentence
  printf '\n'
  if [ "$style" = "grouped" ]; then
    printf '**Template selectors** — each decides whether a template generates for a type at all.\n\n'
    table "templateSelector"
    printf '\n**Options** — each modifies how a selected type is generated.\n\n'
    table "option"
  else
    table ""
  fi
  printf '%s\n' "$END"
}

# ── Splice ────────────────────────────────────────────────────────
# Everything before the start marker, the rendered block, everything after the
# end marker. A file carrying no marker pair is an error naming the file, so a
# target cannot be silently dropped by an edit that removes the markers.
splice() {
  local file="$1" style="$2" rendered="$3"
  grep -qF "$START" "$file" || { echo "FAIL: $file carries no '$START'" >&2; return 1; }
  grep -qF "$END" "$file" || { echo "FAIL: $file carries no '$END'" >&2; return 1; }
  awk -v start="$START" -v end="$END" -v blockfile="$rendered" '
    $0 == start { while ((getline line < blockfile) > 0) print line; skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$file"
}

MODE="check"
case "${1:-}" in
  --write) MODE="write" ;;
  --print) block "${2:-flat}"; exit 0 ;;
  --dump)  dump; exit 0 ;;
  --dump-retired) dump_retired; exit 0 ;;
  "")      MODE="check" ;;
  *)       echo "usage: $0 [--write|--print [flat|grouped]|--dump|--dump-retired]" >&2; exit 2 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STALE=0
for entry in "${TARGETS[@]}"; do
  rel="${entry%%:*}"
  style="${entry##*:}"
  file="$GIT_ROOT/$rel"
  [ -f "$file" ] || { echo "FAIL: no target at $rel" >&2; exit 1; }
  block "$style" > "$TMP/block"
  splice "$file" "$style" "$TMP/block" > "$TMP/rendered"
  if [ "$MODE" = "write" ]; then
    if cmp -s "$file" "$TMP/rendered"; then
      echo "  $rel: already current"
    else
      cp "$TMP/rendered" "$file"
      echo "  $rel: rewritten"
    fi
  elif cmp -s "$file" "$TMP/rendered"; then
    echo "  $rel: current"
  else
    echo "  $rel: STALE — run Scripts/render-annotations.sh --write"
    diff -u "$file" "$TMP/rendered" | sed 's/^/    /'
    STALE=$((STALE + 1))
  fi
done

[ "$STALE" = "0" ] || exit 1
