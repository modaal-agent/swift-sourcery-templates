#!/bin/bash
#
# Agent-skill checks — the skill tree under `skills/` and the two
# `.claude-plugin/` manifests that publish it.
#
# What it holds the skill to: the frontmatter every install channel can parse,
# a body inside the documented budgets, only the file types a plugin directory
# accepts, and no claim about this repository that this repository does not
# back — every `SOURCERY_*` variable the skill writes is one the plugin exports,
# and every `mock-templates` flag, subcommand and quoted line it writes is one
# the CLI declares or prints. SC6 and SC7 compare two sets of names, so rewording a
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
    sed -i.bak 's/"name": "swift-sourcery-mocks"/"name": "swift-sourcery-mock"/' skills/.claude-plugin/plugin.json
    rm -f skills/.claude-plugin/plugin.json.bak
  }

  # SC11 — the plugin root and the skill tree come apart. `source` points at a
  # directory that holds neither the plugin manifest nor the skill.
  mutate_SC11() { sed -i.bak 's|"source": "./skills"|"source": "./Scripts"|' .claude-plugin/marketplace.json && rm -f .claude-plugin/marketplace.json.bak; }

  # SC13 — a grader the runner would refuse: `type:` is the one field it needs
  # to know how to score, and it is checked against a closed set of six.
  mutate_SC13() { sed -i.bak 's/^type: llm$/type: judge/' Tests/Evals/plugin-lane-setup/graders/correct-lane.md && rm -f Tests/Evals/plugin-lane-setup/graders/correct-lane.md.bak; }

  # SC15 — a commit changes the skill and leaves the plugin's version where it
  # was. The copy becomes a git repository of two commits.
  mutate_SC15() {
    git_seed() { git -c user.name=self-test -c user.email=self-test@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null; }
    git_seed init -q && git_seed add -A && git_seed commit -q -m "set the version" &&
      echo "A paragraph." >> skills/swift-sourcery-mocks/references/stream-members.md &&
      git_seed commit -q -am "change the skill, keep the version"
  }

  # SC14 — a quoted line the CLI does not print.
  mutate_SC14_quote() { printf '\n| `mock-templates: <Target> has no generated file` | build it |\n' >> "$S"; }

  # SC14 — a subcommand the CLI does not register.
  mutate_SC14_verb() { printf '\nRun `mock-templates show <Target>`.\n' >> "$S"; }

  # SC16 — a script under the plugin root.
  mutate_SC16_script() { printf '#!/bin/bash\necho ok\n' > skills/swift-sourcery-mocks/print.sh; }

  # SC16 — a package manager's configuration file, whose `.json` is an allowed type.
  mutate_SC16_config() { printf '{}\n' > skills/swift-sourcery-mocks/package.json; }

  # SC16 — a text file holding a NUL byte.
  mutate_SC16_nul() { printf 'a\000b\n' > skills/swift-sourcery-mocks/notes.txt; }

  seed() {
    local check="$1" expected="$2"
    local root="$SELF_TEST_DIR/$check"
    mkdir -p "$root/Tests/Checks"
    cp -R skills "$root/skills"
    cp -R Tests/Evals "$root/Tests/Evals"
    cp -R .claude-plugin "$root/.claude-plugin"
    mkdir -p "$root/Plugins/SourcerySwiftCodegenPlugin" "$root/Sources/mock-templates" "$root/Scripts"
    cp Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift "$root/Plugins/SourcerySwiftCodegenPlugin/"
    cp Sources/mock-templates/*.swift "$root/Sources/mock-templates/"
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
  seed SC13 "SC13"
  seed SC15 "SC15"
  seed SC14_quote "SC14"
  seed SC14_verb "SC14"
  seed SC16_script "SC16"
  seed SC16_config "SC16"
  seed SC16_nul "SC16"

  echo ""
  if [ "$seed_failures" = "0" ]; then
    echo "ALL RED CONTROLS PASSED"
    exit 0
  fi
  echo "$seed_failures RED CONTROL(S) FAILED"
  exit 1
fi

PLUGIN_SOURCE="Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift"
# The CLI's sources: SC7 reads the flags they declare, SC14 the subcommands they
# register and the lines they print.
CLI_SOURCES="$(find Sources/mock-templates -name '*.swift' | sort)"
MARKETPLACE=".claude-plugin/marketplace.json"
# The plugin root is `skills/`, the marketplace entry's `source` (SC11).
PLUGIN_MANIFEST="skills/.claude-plugin/plugin.json"
# The eval cases sit outside the plugin root; a run copies both into one
# directory (CONTRIBUTING.md, "Running the eval suite").
EVAL_DIR="Tests/Evals"

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
# `skills/.claude-plugin/` is the plugin's manifest and icon, not a skill.
SKILLS="$(find skills -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)"
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
  # shellcheck disable=SC2086
  if grep -q "var $camel\b" $CLI_SOURCES || grep -qF "customLong(\"$bare\")" $CLI_SOURCES; then continue; fi
  SC7="$SC7 $flag"
done < "$TMP/flags"
if [ -n "$SC7" ]; then
  fail SC7 "the skill names a flag Sources/mock-templates/ does not declare:$SC7"
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
import json, os, re, sys

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

# Claude Code installs a plugin update only when `version` changes; SC15 holds
# the raise. The icon is the one the directory listing shows.
if plugin is not None:
    version = plugin.get("version")
    if not (isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+", version)):
        problems.append(f"{plugin_path}: version {version!r} is not MAJOR.MINOR.PATCH")
    icon = plugin.get("icon")
    plugin_root = os.path.dirname(os.path.dirname(plugin_path))
    if icon is not None and not os.path.isfile(os.path.join(plugin_root, icon)):
        problems.append(f"{plugin_path}: icon {icon!r} is not a file in the plugin")

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

# ── SC11: the plugin root holds the manifest and loads the skill tree ─
# The plugin root is the marketplace entry's `source`, `./skills`, so an install
# copies the skill and none of the templates, the CLI or the tests. The manifest
# is `<source>/.claude-plugin/plugin.json`, and its `skills` path is what loads
# each skills/<name>/. A `source` pointing anywhere else, or a `skills` path
# that misses a skill directory, means the plugin channel and the other three
# have come apart, and the plugin loader would not report it — it would load no
# skill.
echo ""
echo "── SC11: the entry's \`source\` holds the manifest, which loads skills/<name>/SKILL.md ──"
# shellcheck disable=SC2086
SC11="$(python3 - "$MARKETPLACE" "$PLUGIN_MANIFEST" $SKILLS <<'PY'
import json, os, sys

marketplace_path, manifest_path, skills = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    entries = json.load(open(marketplace_path)).get("plugins", [])
except Exception:
    raise SystemExit  # SC10 reports a manifest that does not parse
for entry in entries:
    name, source = entry.get("name", ""), entry.get("source")
    if not isinstance(source, str) or not source.startswith("./"):
        print(f"{name}: source {source!r} is not a ./ path")
        continue
    root = os.path.normpath(source)
    manifest = os.path.join(root, ".claude-plugin", "plugin.json")
    if os.path.normpath(manifest) != os.path.normpath(manifest_path):
        print(f"{name}: source {source!r} puts the manifest at {manifest}, not {manifest_path}")
        continue
    try:
        plugin = json.load(open(manifest))
    except Exception:
        continue  # SC10
    declared = plugin.get("skills", [])
    declared = [declared] if isinstance(declared, str) else declared
    scanned = [os.path.join(root, path) for path in declared] + [os.path.join(root, "skills")]
    for skill in skills:
        target = os.path.realpath(skill)
        if not os.path.isfile(os.path.join(skill, "SKILL.md")) or not any(
                os.path.realpath(path) == target
                or os.path.realpath(os.path.join(path, os.path.basename(skill))) == target
                for path in scanned):
            print(f"{name}: the plugin at {source!r} loads no {skill}/SKILL.md "
                  f"(its skills paths: {declared or 'none'})")
PY
)"
if [ -n "$SC11" ]; then
  fail SC11 "the plugin root and the skill tree have come apart:"
  printf '%s\n' "$SC11" | sed 's/^/      /'
else
  pass SC11 "the entry's source holds the manifest, whose skills path loads every skill directory"
fi

# ── SC13: every eval case parses ─────────────────────────────────
# The eval suite is the skill's only behavioural gate: each case is run twice,
# once with the plugin loaded and once without, and the two answers compared
# (spec 002, §7.1). The cases live in `Tests/Evals/`, outside the plugin root
# `skills/`, and a run copies the plugin and the cases into one directory — one
# case per directory, `prompt.md` carrying the frontmatter and the user prompt,
# one `graders/<name>.md` per grader, the file name being the grader's name.
#
# The two key sets and the six grader types below are the runner's own, read out
# of the Claude Code binary at 2.1.263 and re-read unchanged at 2.1.267. No CI
# job runs the suite, because it costs model calls, so a mistyped key has to
# fail here rather than at the first run.
#
# SC12 is not used: §6.1 assigned that number to a check for D9's fallback, and
# the fallback was not taken (spec 002, §12.3).
echo ""
echo "── SC13: every eval case parses ──"
if SC13="$(python3 - "$EVAL_DIR" <<'PY'
import os, re, sys

TOP_KEYS = {"schema_version", "name", "description", "tags", "plugins", "runs", "expected_outcome"}
EXECUTION_KEYS = {"model", "max_turns", "timeout_seconds", "allowed_tools", "artifact_publish",
                  "growthbook_overrides", "append_system_prompt", "env"}
GRADER_TYPES = {"regex", "tool_order", "tool_used", "file_exists", "llm", "baseline"}

problems = []
eval_dir = sys.argv[1]
if not os.path.isdir(eval_dir):
    problems.append(f"`{eval_dir}` is not a directory")
    print("\n".join(problems)); raise SystemExit

FRONTMATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*(\n|\Z)", re.S)

def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    match = FRONTMATTER.match(text)
    if match is None:
        problems.append(f"{path}: no frontmatter between `---` markers")
        return None, ""
    keys = {}
    for number, line in enumerate(match.group(1).split("\n"), start=2):
        if not line.strip() or line.startswith((" ", "\t", "#")):
            continue
        key, separator, value = line.partition(":")
        if not separator:
            problems.append(f"{path}:{number}: not `key: value`")
            continue
        keys[key.strip()] = value.strip()
    return keys, text[match.end():]

cases = sorted(entry for entry in os.listdir(eval_dir)
               if os.path.isdir(os.path.join(eval_dir, entry)) and entry != "results")
if not cases:
    problems.append(f"{eval_dir}/ holds no case directory")

for case in cases:
    directory = os.path.join(eval_dir, case)
    prompt_path = os.path.join(directory, "prompt.md")
    if not os.path.isfile(prompt_path):
        problems.append(f"{directory}/: no prompt.md, so the runner reads no case here")
        continue
    keys, body = frontmatter(prompt_path)
    if keys is not None:
        for key in keys:
            if key not in TOP_KEYS and key not in EXECUTION_KEYS:
                problems.append(f"{prompt_path}: unknown frontmatter key `{key}`")
    if not body.strip():
        problems.append(f"{prompt_path}: the body is the user prompt, and it is empty")
    graders_dir = os.path.join(directory, "graders")
    graders = sorted(name for name in os.listdir(graders_dir)) if os.path.isdir(graders_dir) else []
    graders = [name for name in graders if name.endswith(".md")]
    if not graders:
        problems.append(f"{directory}/: no graders/*.md, and a case needs at least one grader")
    for grader in graders:
        grader_path = os.path.join(graders_dir, grader)
        keys, body = frontmatter(grader_path)
        if keys is None:
            continue
        kind = keys.get("type")
        if kind not in GRADER_TYPES:
            problems.append(f"{grader_path}: `type: {kind}` is not one of "
                            + " | ".join(sorted(GRADER_TYPES)))
        elif kind in ("llm", "baseline") and not body.strip():
            problems.append(f"{grader_path}: an `{kind}` grader's body is its criteria, and it is empty")
        elif kind == "regex" and not body.strip():
            problems.append(f"{grader_path}: a `regex` grader's body is its pattern, and it is empty")

print("\n".join(problems))
PY
)" && [ -z "$SC13" ]; then
  pass SC13 "$(find "$EVAL_DIR" -mindepth 1 -maxdepth 1 -type d ! -name results | wc -l | tr -d ' ') case(s) under $EVAL_DIR, $(find "$EVAL_DIR" -path '*/graders/*.md' | wc -l | tr -d ' ') graders"
else
  fail SC13 "a case the runner would refuse:"
  printf '%s\n' "$SC13" | sed 's/^/      /'
fi

# ── SC14: the subcommands the skill names, and the lines it quotes ─
# The skill tells an agent to run `mock-templates <subcommand>` and quotes the
# lines `print` ends with, each with what to do. Every subcommand it writes in
# code has to be one `MockTemplates.swift` registers, and every quoted
# `mock-templates: …` line has to be a string the CLI prints: an argument of
# `print`'s `fail(…)` or `note(…)`, which prepend `mock-templates: `, or a
# literal starting `mock-templates: `. A `<placeholder>` in the quote and a
# `\(…)` interpolation in the source each read as one wildcard (spec 005 §3 D6).
echo ""
echo "── SC14: every \`mock-templates\` subcommand the skill names is registered, and every line it quotes is one the CLI prints ──"
# shellcheck disable=SC2086
SC14="$(python3 - $CLI_SOURCES -- $TREE_FILES <<'PY'
import re, sys

arguments = sys.argv[1:]
split = arguments.index("--")
sources, tree = arguments[:split], arguments[split + 1:]
text = {path: open(path, encoding="utf-8").read() for path in sources}
literal = r'"((?:[^"\\\n]|\\.)*)"'

def wildcard(value):
    out, i = [], 0
    while i < len(value):
        if value.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(value) and depth:
                depth += {"(": 1, ")": -1}.get(value[j], 0)
                j += 1
            out.append("<*>")
            i = j
        else:
            out.append(value[i])
            i += 1
    return "".join(out)

printed = set()
for path, source in text.items():
    for match in re.finditer(r"\b(?:fail|note)\(\s*" + literal, source):
        printed.add("mock-templates: " + wildcard(match.group(1)))
    for match in re.finditer(literal, source):
        if match.group(1).startswith("mock-templates: "):
            printed.add(wildcard(match.group(1)))

def kebab(name):
    return re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()

registered = set()
everything = "\n".join(text.values())
for listing in re.findall(r"subcommands:\s*\[([^\]]*)\]", everything):
    for type_name in re.findall(r"(\w+)\.self", listing):
        body = re.search(r"struct " + type_name + r"\b(.*?)(?=\nstruct |\Z)", everything, re.S)
        named = re.search(r'commandName:\s*"([^"]+)"', body.group(1)) if body else None
        registered.add(named.group(1) if named else kebab(type_name))

problems = []
quoted = 0
tick = chr(96)  # a backtick, kept out of this heredoc
for path in tree:
    document = open(path, encoding="utf-8").read()
    fence = re.compile("^" + tick * 3 + r"[^\n]*\n(.*?)^" + tick * 3, re.S | re.M)
    fenced = fence.findall(document)
    spans = re.findall(tick + "([^" + tick + r"\n]+)" + tick, fence.sub("", document))
    for code in fenced + spans:
        for verb in re.findall(r"\bmock-templates[ \t]+([a-z][a-z-]*)", code):
            if verb not in registered:
                problems.append(f"{path}: mock-templates {verb} is not a subcommand ({', '.join(sorted(registered))})")
    for span in spans:
        if span.startswith("mock-templates: "):
            quoted += 1
            line = re.sub(r"<[^>]*>", "<*>", span)
            if line not in printed:
                problems.append(f"{path}: quoted, and printed by no line of the CLI: {span}")
print("\n".join(problems) if problems else f"OK {len(registered)} {quoted}")
PY
)"
case "$SC14" in
  "OK "*)
    set -- $SC14
    pass SC14 "$2 subcommands registered, $3 quoted line(s), each printed by the CLI" ;;
  *)
    fail SC14 "the skill describes a CLI that does not do what it says:"
    printf '%s\n' "$SC14" | sed 's/^/      /' ;;
esac

# ── SC15: a change under the plugin root raises the plugin's version ─
# Claude Code installs a plugin update only when `version` in the manifest
# changes, so an edit under `skills/` that leaves the version where it was
# reaches no user. The check takes the oldest commit of the unbroken run of
# manifest commits that carry the current version — the commit that set it —
# and fails when a file under `skills/` differs from that commit or is
# untracked. It reads git history: outside a checkout, or in a shallow clone, it
# prints a note and is skipped, so the `skills` job checks out with
# `fetch-depth: 0`.
echo ""
echo "── SC15: a change under skills/ raises the plugin's version ──"
SC15="$(python3 - "$PLUGIN_MANIFEST" 2>"$TMP/sc15-note" <<'PY'
import json, os, subprocess, sys

manifest = sys.argv[1]
plugin_root = os.path.dirname(os.path.dirname(manifest))
try:
    version = json.load(open(manifest)).get("version")
except Exception:
    raise SystemExit  # SC10 reports a manifest that does not parse
if not isinstance(version, str):
    raise SystemExit  # SC10 reports a missing version

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)

top = git("rev-parse", "--show-toplevel")
if top.returncode or os.path.realpath(top.stdout.strip()) != os.path.realpath("."):
    print("not a git checkout, so the version was not compared with history", file=sys.stderr)
    raise SystemExit
if git("rev-parse", "--is-shallow-repository").stdout.strip() == "true":
    print("a shallow clone; the check needs the full history (fetch-depth: 0)", file=sys.stderr)
    raise SystemExit
base = None
for commit in git("log", "--format=%H", "--", manifest).stdout.split():
    shown = git("show", f"{commit}:{manifest}")
    try:
        committed = json.loads(shown.stdout).get("version") if shown.returncode == 0 else None
    except ValueError:
        committed = None
    if committed != version:
        break
    base = commit
if base is None:
    raise SystemExit  # the working tree sets or raises the version, and it is not committed yet
changed = git("diff", "--name-only", base, "--", plugin_root).stdout.splitlines()
changed += git("ls-files", "--others", "--exclude-standard", "--", plugin_root).stdout.splitlines()
changed = sorted({path for path in changed if path})
if changed:
    listed = ", ".join(changed[:3]) + (", …" if len(changed) > 3 else "")
    print(f"{plugin_root}/ changed since {base[:12]}, which set version {version} ({listed}): "
          f"raise `version` in {manifest}")
PY
)"
if [ -s "$TMP/sc15-note" ]; then
  echo "  SC15: skipped — $(cat "$TMP/sc15-note")"
elif [ -n "$SC15" ]; then
  fail SC15 "the skill changed and the plugin's version did not:"
  printf '%s\n' "$SC15" | sed 's/^/      /'
else
  pass SC15 "version $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN_MANIFEST") covers every change under skills/"
fi

# ── SC16: the plugin root holds only the file types a directory accepts ─
# A plugin directory accepts, from an organization it has not verified,
# Markdown, text, JSON, YAML and PNG, JPEG, GIF, WebP and ICO images, and
# refuses a file that starts with `#!`, a package manager's configuration file,
# and a text file that is not UTF-8 or holds a NUL byte. The check reads what a
# push publishes: in a git checkout the tracked files and the untracked ones
# git does not ignore, otherwise every file under `skills/`. An image is
# checked by its first bytes, so a script renamed `.png` is refused too.
echo ""
echo "── SC16: every file under skills/ is a type a plugin directory accepts ──"
SC16="$(python3 - <<'PY'
import os, subprocess

TEXT = {".md", ".txt", ".json", ".yaml", ".yml"}
IMAGES = {
    ".png": lambda d: d.startswith(b"\x89PNG\r\n\x1a\n"),
    ".jpg": lambda d: d.startswith(b"\xff\xd8\xff"),
    ".jpeg": lambda d: d.startswith(b"\xff\xd8\xff"),
    ".gif": lambda d: d.startswith((b"GIF87a", b"GIF89a")),
    ".webp": lambda d: d[:4] == b"RIFF" and d[8:12] == b"WEBP",
    ".ico": lambda d: d.startswith(b"\x00\x00\x01\x00"),
}
TEXT_NAMES = {"LICENSE", "README", ".gitignore"}
PACKAGE_CONFIGS = {
    "pnpm-workspace.yaml", "package.json", "package-lock.json", "yarn.lock", ".npmrc",
    "Package.swift", "Package.resolved", "Gemfile", "requirements.txt", "pyproject.toml",
    "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "Cargo.toml", "go.mod",
}

def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)

top = git("rev-parse", "--show-toplevel")
if top.returncode == 0 and os.path.realpath(top.stdout.strip()) == os.path.realpath("."):
    listed = git("ls-files", "--", "skills").stdout.splitlines()
    listed += git("ls-files", "--others", "--exclude-standard", "--", "skills").stdout.splitlines()
else:
    listed = [os.path.join(d, f) for d, _, files in os.walk("skills") for f in files]
files = sorted({path for path in listed if os.path.isfile(path)})

problems = []
for path in files:
    name = os.path.basename(path)
    extension = os.path.splitext(name)[1].lower()
    data = open(path, "rb").read()
    if name in PACKAGE_CONFIGS:
        problems.append(f"{path}: a package manager's configuration file")
    if data.startswith(b"#!"):
        problems.append(f"{path}: starts with #!")
    if extension in IMAGES:
        if not IMAGES[extension](data):
            problems.append(f"{path}: its first bytes are not a {extension[1:].upper()} image's")
    elif extension in TEXT or name in TEXT_NAMES:
        if b"\x00" in data:
            problems.append(f"{path}: holds a NUL byte")
        try:
            data.decode("utf-8")
        except UnicodeDecodeError as error:
            problems.append(f"{path}: not UTF-8 ({error.reason} at byte {error.start})")
    else:
        problems.append(f"{path}: {extension or name} is not Markdown, text, JSON, YAML or an allowed image")
print("\n".join(problems) if problems else f"OK {len(files)}")
PY
)"
case "$SC16" in
  "OK "*)
    pass SC16 "${SC16#OK } file(s), each Markdown, text, JSON, YAML or an allowed image, none starting with #!" ;;
  *)
    fail SC16 "a file the plugin directory refuses:"
    printf '%s\n' "$SC16" | sed 's/^/      /' ;;
esac

# ── Result ────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" = "0" ]; then
  echo "ALL SKILL CHECKS PASSED"
else
  echo "$FAILURES SKILL CHECK(S) FAILED"
  exit 1
fi
