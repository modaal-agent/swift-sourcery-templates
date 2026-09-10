#!/bin/bash
#
# Agent-skill checks — the skill tree under `skills/` and the two
# `.claude-plugin/` manifests that publish it.
#
# What it holds the skill to: the frontmatter every install channel can parse,
# a body inside the documented budgets, and no claim about this repository that
# this repository does not back — every `SOURCERY_*` variable the skill writes
# is one the plugin exports, and every `mock-templates` flag it writes is one
# the CLI declares. SC6 and SC7 compare two sets of names, so rewording a
# sentence on either side leaves them green; that comparison is the whole reason
# the skill lives in this repository rather than in one of its own (spec 002,
# §8 D15).
#
# Reads markdown and JSON with `grep`, `awk` and `python3`. No Swift toolchain,
# no Sourcery, no network, so this runs on ubuntu in seconds, ungated beside
# `rules` and `annotations`: a push that edits only the skill is a
# markdown-only push, which skips every macOS lane.
#
# The annotation table inside the skill is `run-annotation-checks.sh`'s AC6 and
# AC8, not this script's.
#
# Usage:
#   Tests/Checks/run-skill-checks.sh
#   Tests/Checks/run-skill-checks.sh --self-test   # each check red on a seeded violation

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$GIT_ROOT" || exit 1

if [ "${1:-}" = "--self-test" ]; then
  # ── Red controls ────────────────────────────────────────────────
  # One mutation per check, applied inside a temporary copy of the files this
  # script reads. Each declares the exact set of checks it must turn red — a
  # set, because some checks are downstream of others: a renamed skill
  # directory moves every relative path the marketplace entry resolves through.
  SELF_TEST_DIR="$(mktemp -d)"
  trap 'rm -rf "$SELF_TEST_DIR"' EXIT
  seed_failures=0
  S=skills/swift-sourcery-mocks/SKILL.md

  # SC1 — a plain scalar carrying `: `, which is what the `skills` CLI's YAML
  # parser rejected on the first run of phase B1's gate.
  mutate_SC1() { sed -i.bak 's/^description: Generate/description: Generate mocks: /' "$S" && rm -f "$S.bak"; }

  # SC2 — `name:` no longer matches the directory.
  mutate_SC2() { sed -i.bak 's/^name: swift-sourcery-mocks$/name: sourcery-mocks/' "$S" && rm -f "$S.bak"; }

  # SC3 — a Claude Code extension key the Skills API rejects.
  mutate_SC3() { sed -i.bak 's/^license: Apache-2.0$/argument-hint: [protocol]/' "$S" && rm -f "$S.bak"; }

  # SC4 — an empty description.
  mutate_SC4() { sed -i.bak 's/^description: .*$/description:/' "$S" && rm -f "$S.bak"; }

  # SC5 — a body over budget.
  mutate_SC5() { for _ in $(seq 1 400); do echo "padding" >> "$S"; done; }

  # SC6 — a variable the plugin does not export.
  mutate_SC6() { printf '\nWrite `${SOURCERY_MODULE_ROOT}` in `sources:`.\n' >> "$S"; }

  # SC7 — a flag the CLI does not declare.
  mutate_SC7() { printf '\nRun `mock-templates validate --strict`.\n' >> "$S"; }

  # SC8 — a link to a file that is not there.
  mutate_SC8() { printf '\nSee [references/xcode.md](references/xcode.md).\n' >> "$S"; }

  # SC9 — a version pinned in a snippet.
  mutate_SC9() { printf '\n    .package(url: "…", from: "0.8.0"),\n' >> "$S"; }

  # SC10 — the two manifests name different plugins.
  mutate_SC10() {
    sed -i.bak 's/"name": "swift-sourcery-mocks"/"name": "swift-sourcery-mock"/' .claude-plugin/plugin.json
    rm -f .claude-plugin/plugin.json.bak
  }

  # SC11 — the plugin root and the skill tree come apart. `source` points at a
  # directory that holds no `skills/<name>/SKILL.md`.
  mutate_SC11() { sed -i.bak 's|"source": "./"|"source": "./Scripts"|' .claude-plugin/marketplace.json && rm -f .claude-plugin/marketplace.json.bak; }

  seed() {
    local check="$1" expected="$2"
    local root="$SELF_TEST_DIR/$check"
    mkdir -p "$root/Tests/Checks"
    cp -R skills "$root/skills"
    cp -R .claude-plugin "$root/.claude-plugin"
    mkdir -p "$root/Plugins/SourcerySwiftCodegenPlugin" "$root/Sources/mock-templates" "$root/Scripts"
    cp Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift "$root/Plugins/SourcerySwiftCodegenPlugin/"
    cp Sources/mock-templates/Commands.swift "$root/Sources/mock-templates/"
    cp "$SCRIPT_DIR/run-skill-checks.sh" "$root/Tests/Checks/"
    if ! ( cd "$root" && "mutate_$check" ); then
      echo "  $check: FAIL — the mutation itself did not apply"
      seed_failures=$((seed_failures + 1))
      return
    fi
    local out reds
    out="$("$root/Tests/Checks/run-skill-checks.sh" 2>&1)"
    reds="$(printf '%s\n' "$out" | grep -oE '^  SC[0-9]+: FAIL' | grep -oE 'SC[0-9]+' | sort -uV | tr '\n' ' ')"
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
  seed SC1 "SC1"
  seed SC2 "SC2"
  seed SC3 "SC3"
  seed SC4 "SC4"
  seed SC5 "SC5"
  seed SC6 "SC6"
  seed SC7 "SC7"
  seed SC8 "SC8"
  seed SC9 "SC9"
  seed SC10 "SC10"
  seed SC11 "SC11"

  echo ""
  if [ "$seed_failures" = "0" ]; then
    echo "ALL RED CONTROLS PASSED"
    exit 0
  fi
  echo "$seed_failures RED CONTROL(S) FAILED"
  exit 1
fi

PLUGIN_SOURCE="Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift"
CLI_SOURCE="Sources/mock-templates/Commands.swift"
MARKETPLACE=".claude-plugin/marketplace.json"
PLUGIN_MANIFEST=".claude-plugin/plugin.json"

# The Agent Skills standard's six keys. Claude Code accepts fourteen more; the
# Skills API and claude.ai reject every one of them by name, so a skill that has
# to stay uploadable carries none (spec 002, §4.4 and §8 D6).
ALLOWED_KEYS="name description license compatibility metadata allowed-tools"
DESCRIPTION_MAX=1024
SKILL_MAX_LINES=400
REFERENCE_MAX_LINES=250

FAILURES=0
pass() { echo "  $1: ok — $2"; }
fail() { echo "  $1: FAIL — $2"; FAILURES=$((FAILURES + 1)); }

[ -d skills ] || { echo "FAIL: no skills/ directory"; exit 1; }
SKILLS="$(find skills -mindepth 1 -maxdepth 1 -type d | sort)"
[ -n "$SKILLS" ] || { echo "FAIL: skills/ holds no skill directory"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TREE_FILES="$(find skills -type f -name '*.md' | sort)"

echo ""
echo "── skills ──"
for dir in $SKILLS; do
  echo "  $dir: $(find "$dir" -type f | wc -l | tr -d ' ') files"
done

# ── SC1: the frontmatter every channel can parse ─────────────────
# `---` on line 1, one `key: value` per line, and no unquoted value carrying
# `: `. The last rule is not pedantry: the `skills` CLI parses this block with a
# strict YAML parser and refuses the file with "Nested mappings are not allowed
# in compact mappings", while Claude Code's own loader accepts it — measured in
# phase B1 on a description whose sentence used a colon.
echo ""
echo "── SC1: the frontmatter opens at line 1 and parses ──"
SC1=""
for dir in $SKILLS; do
  file="$dir/SKILL.md"
  if [ ! -f "$file" ]; then
    SC1="$SC1
$dir: no SKILL.md"
    continue
  fi
  SC1="$SC1$(awk -v f="$file" '
    NR == 1 { if ($0 != "---") { printf "\n%s:1: line 1 is `%s`, not `---`\n", f, $0; exit } ; next }
    !closed && $0 == "---" { closed = 1; next }
    closed { next }
    /^[ \t]*$/ { next }
    /^  [A-Za-z_][A-Za-z0-9_-]*:( |$)/ { line = $0; sub(/^  [A-Za-z0-9_-]+: ?/, "", line); value = line; nested = 1 }
    !nested && /^[A-Za-z_][A-Za-z0-9_-]*:( |$)/ { line = $0; sub(/^[A-Za-z0-9_-]+: ?/, "", line); value = line }
    {
      if (!nested && $0 !~ /^[A-Za-z_][A-Za-z0-9_-]*:( |$)/ && $0 !~ /^  [A-Za-z_][A-Za-z0-9_-]*:( |$)/) {
        printf "\n%s:%d: not `key: value` — the frontmatter is one key per line\n", f, NR
      } else if (value != "" && value !~ /^["'"'"']/ && index(value, ": ") > 0) {
        printf "\n%s:%d: an unquoted value carries `: `, which a strict YAML parser refuses\n", f, NR
      }
      nested = 0; value = ""
    }
    END { if (!closed) printf "\n%s: the frontmatter is never closed by `---`\n", f }
  ' "$file")"
done
if [ -n "${SC1//[[:space:]]/}" ]; then
  fail SC1 "the frontmatter does not parse:"
  printf '%s\n' "$SC1" | grep -v '^$' | sed 's/^/      /'
else
  pass SC1 "$(printf '%s\n' "$SKILLS" | wc -l | tr -d ' ') skill(s), frontmatter at line 1, one key per line"
fi

# Parse the frontmatter of each skill into <dir>\t<key>\t<value> for the checks
# below. Nested keys are recorded under their parent as `parent.key`.
for dir in $SKILLS; do
  awk -v dir="$dir" '
    NR == 1 && $0 == "---" { open = 1; next }
    open && $0 == "---" { exit }
    open && /^[A-Za-z_][A-Za-z0-9_-]*:/ { key = $0; sub(/:.*$/, "", key); value = $0; sub(/^[A-Za-z0-9_-]+: ?/, "", value); parent = key; printf "%s\t%s\t%s\n", dir, key, value; next }
    open && /^  [A-Za-z_][A-Za-z0-9_-]*:/ { key = $0; sub(/^  /, "", key); sub(/:.*$/, "", key); value = $0; sub(/^  [A-Za-z0-9_-]+: ?/, "", value); printf "%s\t%s.%s\t%s\n", dir, parent, key, value }
  ' "$dir/SKILL.md" 2>/dev/null
done > "$TMP/frontmatter"

field() {  # field <dir> <key> → value
  awk -F'\t' -v d="$1" -v k="$2" '$1 == d && $2 == k { print $3; exit }' "$TMP/frontmatter"
}

# ── SC2: `name:` is the directory, and is not `synced` ───────────
echo ""
echo "── SC2: \`name:\` equals the containing directory ──"
SC2=""
for dir in $SKILLS; do
  base="$(basename "$dir")"
  name="$(field "$dir" name)"
  if [ "$name" != "$base" ]; then
    SC2="$SC2 $dir(name='$name')"
  elif [ "$name" = "synced" ]; then
    SC2="$SC2 $dir(reserved under ~/.claude/skills/)"
  fi
done
if [ -n "$SC2" ]; then
  fail SC2 "a skill is invoked by its directory name, so the two cannot differ:$SC2"
else
  pass SC2 "every skill's \`name:\` is its directory"
fi

# ── SC3: only the Agent Skills standard's keys ───────────────────
echo ""
echo "── SC3: frontmatter keys are the standard's six ──"
SC3=""
for dir in $SKILLS; do
  for key in $(awk -F'\t' -v d="$dir" '$1 == d && $2 !~ /\./ { print $2 }' "$TMP/frontmatter"); do
    case " $ALLOWED_KEYS " in
      *" $key "*) ;;
      *) SC3="$SC3 $dir:$key" ;;
    esac
  done
done
if [ -n "$SC3" ]; then
  fail SC3 "packaging for the Skills API rejects a Claude Code extension key by name:$SC3"
else
  pass SC3 "keys ⊆ {$(echo $ALLOWED_KEYS | tr ' ' ',')}"
fi

# ── SC4: the description is present and within budget ────────────
echo ""
echo "── SC4: \`description:\` is 1–$DESCRIPTION_MAX characters ──"
SC4=""
SIZES=""
for dir in $SKILLS; do
  description="$(field "$dir" description)"
  size="${#description}"
  SIZES="$SIZES $(basename "$dir")=$size"
  if [ "$size" = "0" ]; then
    SC4="$SC4 $dir(empty — it is the only thing auto-invocation reads)"
  elif [ "$size" -gt "$DESCRIPTION_MAX" ]; then
    SC4="$SC4 $dir($size > $DESCRIPTION_MAX)"
  fi
done
if [ -n "$SC4" ]; then
  fail SC4 "the description is resident in every session, used or not:$SC4"
else
  pass SC4 "characters:$SIZES"
fi

# ── SC5: the body and each reference within budget ───────────────
# The body stays in context across every turn after the skill is invoked; a
# reference costs nothing until the agent opens it.
echo ""
echo "── SC5: SKILL.md ≤ $SKILL_MAX_LINES lines, each reference ≤ $REFERENCE_MAX_LINES ──"
SC5=""
LONGEST=0
for file in $TREE_FILES; do
  lines="$(wc -l < "$file" | tr -d ' ')"
  [ "$lines" -gt "$LONGEST" ] && LONGEST="$lines"
  case "$file" in
    */SKILL.md) [ "$lines" -gt "$SKILL_MAX_LINES" ] && SC5="$SC5 $file($lines > $SKILL_MAX_LINES)" ;;
    *) [ "$lines" -gt "$REFERENCE_MAX_LINES" ] && SC5="$SC5 $file($lines > $REFERENCE_MAX_LINES)" ;;
  esac
done
if [ -n "$SC5" ]; then
  fail SC5 "over budget:$SC5"
else
  pass SC5 "$(printf '%s\n' "$TREE_FILES" | wc -l | tr -d ' ') files, longest $LONGEST lines"
fi

# ── SC6: every SOURCERY_* name the skill writes is exported ──────
# The plugin builds two of these by interpolation — `SOURCERY_TARGET_\(name)` —
# so the set read out of its source carries the prefix `SOURCERY_TARGET_`, and a
# name the skill writes matches either literally or by one of those prefixes.
echo ""
echo "── SC6: every \`SOURCERY_*\` name is one the plugin exports ──"
grep -oh 'SOURCERY_[A-Z0-9_]*' "$PLUGIN_SOURCE" | sort -u > "$TMP/exported"
# shellcheck disable=SC2086
grep -oh 'SOURCERY_[A-Za-z0-9_]*' $TREE_FILES | sort -u > "$TMP/written"
SC6=""
while read -r name; do
  [ -z "$name" ] && continue
  if grep -qx -- "$name" "$TMP/exported"; then continue; fi
  matched=""
  while read -r prefix; do
    case "$prefix" in
      *_) case "$name" in "$prefix"*) matched=1 ;; esac ;;
    esac
  done < "$TMP/exported"
  [ -z "$matched" ] && SC6="$SC6 $name"
done < "$TMP/written"
if [ -n "$SC6" ]; then
  fail SC6 "the skill names a variable $PLUGIN_SOURCE does not export:$SC6"
else
  pass SC6 "$(wc -l < "$TMP/written" | tr -d ' ') names written, all exported"
fi

# ── SC7: every mock-templates flag the skill writes is declared ──
# A long flag is collected from a line naming `mock-templates`, and from every
# line of a fenced block that names it — a flag on its own continuation line
# belongs to the command above it. ArgumentParser derives `--bundle-version`
# from `var bundleVersion`, so a kebab-case flag is compared against its
# camelCase declaration as well as against a `customLong` spelling.
echo ""
echo "── SC7: every \`mock-templates\` flag is one the CLI declares ──"
# shellcheck disable=SC2086
awk '
  /^```/ { if (inblock) { if (blocktext ~ /mock-templates/) print blocktext; inblock = 0; blocktext = "" } else inblock = 1; next }
  inblock { blocktext = blocktext "\n" $0; next }
  /mock-templates/ { print }
  END { if (inblock && blocktext ~ /mock-templates/) print blocktext }
' $TREE_FILES | grep -oE '\-\-[a-z][a-z-]+' | sort -u > "$TMP/flags"
SC7=""
while read -r flag; do
  [ -z "$flag" ] && continue
  bare="${flag#--}"
  camel="$(printf '%s' "$bare" | awk -F- '{ out = $1; for (i = 2; i <= NF; i++) out = out toupper(substr($i, 1, 1)) substr($i, 2); print out }')"
  if grep -q "var $camel\b" "$CLI_SOURCE" || grep -qF "customLong(\"$bare\")" "$CLI_SOURCE"; then continue; fi
  SC7="$SC7 $flag"
done < "$TMP/flags"
if [ -n "$SC7" ]; then
  fail SC7 "the skill names a flag $CLI_SOURCE does not declare:$SC7"
else
  pass SC7 "$(wc -l < "$TMP/flags" | tr -d ' ') flags written, all declared"
fi

# ── SC8: every relative link resolves ────────────────────────────
echo ""
echo "── SC8: every relative link resolves to a file ──"
SC8=""
for file in $TREE_FILES; do
  dir="$(dirname "$file")"
  for target in $(grep -oE '\]\([^)]+\)' "$file" | sed 's/^](//; s/)$//' | grep -vE '^(https?:|mailto:|#)' | sed 's/#.*$//' | sort -u); do
    [ -z "$target" ] && continue
    [ -e "$dir/$target" ] || SC8="$SC8 ${file}→${target}"
  done
done
if [ -n "$SC8" ]; then
  fail SC8 "a link points at a file that is not there:$SC8"
else
  pass SC8 "every relative link resolves"
fi

# ── SC9: no version literal anywhere in the tree ─────────────────
# A pin in a snippet is wrong the day after the next tag, and nothing in the
# adopter's repository reads it. Snippets carry a placeholder and the command
# that resolves the newest tag (spec 002, §8 D7).
echo ""
echo "── SC9: no version literal in the skill tree ──"
# shellcheck disable=SC2086
SC9="$(grep -nE '[0-9]+\.[0-9]+\.[0-9]+' $TREE_FILES)"
if [ -n "$SC9" ]; then
  fail SC9 "a version is pinned where nothing will update it:"
  printf '%s\n' "$SC9" | sed 's/^/      /'
else
  pass SC9 "no semver literal"
fi

# ── SC10: the two manifests parse and agree ──────────────────────
echo ""
echo "── SC10: both \`.claude-plugin\` manifests parse and name one plugin ──"
if SC10="$(python3 - "$MARKETPLACE" "$PLUGIN_MANIFEST" <<'PY'
import json, sys

marketplace_path, plugin_path = sys.argv[1], sys.argv[2]
problems = []
try:
    marketplace = json.load(open(marketplace_path))
except Exception as error:
    problems.append(f"{marketplace_path}: {error}")
    marketplace = None
try:
    plugin = json.load(open(plugin_path))
except Exception as error:
    problems.append(f"{plugin_path}: {error}")
    plugin = None

if marketplace is not None:
    for key in ("name", "owner", "plugins"):
        if key not in marketplace:
            problems.append(f"{marketplace_path}: no `{key}` key, which is required")
    if not isinstance(marketplace.get("owner"), dict) or "name" not in marketplace.get("owner", {}):
        problems.append(f"{marketplace_path}: `owner.name` is required")
    for entry in marketplace.get("plugins", []):
        for key in ("name", "source"):
            if key not in entry:
                problems.append(f"{marketplace_path}: a plugin entry has no `{key}`")

if plugin is not None and "name" not in plugin:
    problems.append(f"{plugin_path}: no `name` key, which is the one required key")

if marketplace is not None and plugin is not None:
    names = [entry.get("name") for entry in marketplace.get("plugins", [])]
    if plugin.get("name") not in names:
        problems.append(
            f"`{plugin.get('name')}` in {plugin_path} is not among {names} in {marketplace_path}"
        )

print("\n".join(problems))
PY
)" && [ -z "$SC10" ]; then
  pass SC10 "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["plugins"]))' "$MARKETPLACE") plugin entry, named the same on both sides"
else
  fail SC10 "a manifest was edited on one side only:"
  printf '%s\n' "$SC10" | sed 's/^/      /'
fi

# ── SC11: the plugin root still holds the skill tree ─────────────
# With `source: "./"` the plugin root is the marketplace root and its default
# `skills/` is the tree the other three channels read. A `source` pointing
# anywhere else means the plugin channel and the rest have come apart, and the
# plugin loader would not report it — it would load no skill.
echo ""
echo "── SC11: the marketplace entry's \`source\` holds skills/<name>/SKILL.md ──"
SC11=""
while IFS=$'\t' read -r name source; do
  [ -z "$name" ] && continue
  root="${source%/}"
  [ -z "$root" ] && root="."
  case "$root" in /*) SC11="$SC11 $name(source '$source' is absolute)"; continue ;; esac
  found=""
  for dir in $SKILLS; do
    [ -f "$root/$dir/SKILL.md" ] && found="$found $dir"
  done
  if [ -z "$found" ]; then
    SC11="$SC11 $name(no skills/<name>/SKILL.md under '$source')"
  fi
done < <(python3 -c '
import json, sys
marketplace = json.load(open(sys.argv[1]))
for entry in marketplace.get("plugins", []):
    source = entry.get("source")
    if isinstance(source, str):
        print(entry.get("name", ""), source, sep="\t")
' "$MARKETPLACE" 2>/dev/null)
if [ -n "$SC11" ]; then
  fail SC11 "the plugin root and the skill tree have come apart:$SC11"
else
  pass SC11 "every entry's source holds the tree the other channels read"
fi

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" = "0" ]; then
  echo "ALL SKILL CHECKS PASSED"
else
  echo "$FAILURES SKILL CHECK(S) FAILED"
  exit 1
fi
