# Eval cases for the agent skill

Five prompts, from spec 002 §7.1. Each is a question an adopter asks in a repository that uses these
templates, and each has one correct lane or one correct diagnosis. Every case is run twice — once
with `swift-sourcery-mocks` loaded and once without it — and the two answers are compared. That
comparison is the only measure of whether `skills/swift-sourcery-mocks/SKILL.md` changes what an
agent does; a prompt whose with-skill answer is wrong is a defect in the skill's text, so edit the
skill and run that case again.

| case | the prompt asks | correct |
| --- | --- | --- |
| `plugin-lane-setup` | mock generation for a package with a test target | the build-tool plugin, a config naming `Mocks`, no `output:` |
| `commit-generated-mocks` | mocks committed so consumers run no generator | `mock-templates generate`, with `validate` in CI |
| `cross-module-protocol` | a protocol declared in another module | `${SOURCERY_SOURCES}`, and another `--sources` on the CLI lane |
| `does-not-conform` | why `PaymentsMock` does not conform to `Refunding` | the refined protocol was not among the parsed sources |
| `publisher-hangs` | why a test awaiting the mock's publisher hangs | the backing `PassthroughSubject` does not replay |
| `member-names` | which members a mock gives for underscored names and an overload group | the declared name verbatim; the fewest-parameter overload keeps it, the rest take their argument labels |

## Running them

From the repository root, which is the plugin root:

```bash
claude plugin eval . --ablation with-without
```

`.claude-plugin/plugin.json` names this directory in `experimental.evals`, so no `--eval-dir` is
needed. Results land in `Tests/Evals/results/`, which is not committed. The runner is in early
access: a Claude Code that has not been granted it answers "`plugin eval` is currently in early
access" and runs nothing.

Without the runner, run one case's two arms by hand and read both answers:

```bash
REPO=/path/to/swift-sourcery-templates
PROMPT="$(awk 'NR==1 && $0=="---" { fm=1; next } fm && $0=="---" { fm=0; next } !fm' \
  "$REPO/Tests/Evals/plugin-lane-setup/prompt.md")"
ARGS=(-p --restricted --strict-mcp-config --allowedTools "Read,Glob,Grep,Skill" --permission-prompts none)

cd "$(mktemp -d)" && claude "${ARGS[@]}" "$PROMPT"                       # without
cd "$(mktemp -d)" && claude "${ARGS[@]}" --plugin-dir "$REPO" "$PROMPT"  # with
```

`--plugin-dir` loads the plugin for that session only, so the without-arm needs nothing uninstalled.
Three things the arms are sensitive to, each measured on a run that got them wrong:

- **Run from a directory whose path does not name this repository.** The file tools take absolute
  paths, and a without-arm that reads the repository is answering with the skill's material by
  another route. A first pass ran the arms under the session scratchpad, whose path carries the
  repository name; two without-arms read `templates/Mocks/MockVar.swift` and
  `references/cli-lane.md` and answered from them.
- **`--restricted` confines the file tools to the run directory**, which is what makes the point
  above hold. It also removes Bash, so an answer cannot resolve the newest tag with `git ls-remote`
  and says so instead.
- **Under `--restricted` the with-arm cannot open `references/*.md` either** — they are outside the
  run directory — so what it answers from is `SKILL.md` alone. Add
  `--add-dir "$REPO/skills/swift-sourcery-mocks"` to the with-arm when a case is meant to exercise a
  reference file.

Each arm has to be a fresh session: context left over from writing the skill hides what the skill
does not say.

## Writing a case

One directory per case, holding `prompt.md` and `graders/`. The prompt's frontmatter carries
`description`, `tags`, `expected_outcome`, and the execution keys `allowed_tools` and `max_turns`;
its body is the user message. Each grader is one `graders/<name>.md`, the file name is the grader's
name, the frontmatter carries `type` — `regex`, `llm`, `tool_used`, `tool_order`, `file_exists` or
`baseline` — and the body is the criteria for an `llm` grader and the pattern for a `regex` one.
`arm: with-only` marks a grader that measures whether the skill fired rather than whether the answer
is right, and keeps it out of the score.

The eval directory cannot live under `skills/`: it is the plugin's skill component directory, and
the runner refuses a case directory inside one.
