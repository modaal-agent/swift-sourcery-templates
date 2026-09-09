# Agent rules

Rules for working in this repository. They are the additions to [CONTRIBUTING.md](CONTRIBUTING.md),
not a summary of it.

`AGENTS.md` and `CLAUDE.md` are one file kept in two places, byte for byte. Edit `AGENTS.md`, then
`cp AGENTS.md CLAUDE.md`; CI fails if they differ. This repository once carried different material
in each and the copies drifted.

**Read first, by question:**

| you need | read |
| --- | --- |
| what the templates generate, how to consume them, the annotation list | [README.md](README.md) |
| how the templates are built, where to change what, the pitfalls already hit | [CONTRIBUTING.md](CONTRIBUTING.md) |
| what changed in a release and what it breaks | [CHANGELOG.md](CHANGELOG.md) |
| which fixture covers which construct | [Tests/Checks/README.md](Tests/Checks/README.md) |
| the plan for a change too big to carry in a commit message | [specs/](specs/) |

Run from the repository root:

```bash
Tests/Checks/run-checks.sh              # ~10s — snapshot, both language modes, behaviour
Tests/Checks/run-checks.sh --record     # only after reading the diff the line above printed
```

## Writing style: state facts and actions, no aphorisms

**Scope: every character of prose you produce for this project.** Specs, docs, code comments, commit
messages, PR bodies, review findings, and **your replies in chat**. There is no "informal" channel
where this relaxes.

**The test, applied to each sentence:** does it give the reader **a fact they can verify** or **an
action they can take**, with the referent named — the file, the line, the setting, the command, the
number? If it does neither, delete it. A sentence that only characterizes the work, dramatizes a
finding, or summarizes how significant something is carries no information the reader can act on.

Habits to avoid (common LLM-isms):

- **Mannered prose** substitutes metaphor and flourish for direct statement. Instead of "a parameter
  worth varying," the mannered writer produces "a dial worth turning." Instead of "this point still
  matters," they write "this point earns its keep." The phrases exist to display the writer, not to
  convey the idea, and readers can tell. That is why mannered prose irritates: it makes the reader
  work harder so the writer can perform. It is also imprecise — metaphors drag in connotations the
  writer did not choose and cannot control. **The fix is to say what you mean. When a literal phrase
  is available, use it.**
- **Aphoristic juxtapositions** ("Free now, a second migration later"). State the trade-off
  explicitly: what it costs now, what it costs later, which option you recommend.
- **Dramatic reversals and punchlines** ("that direction has reversed"; "upgraded those steps from
  redundant to breaking"). Give the before value, the after value, and the date measured.
- **Negative-space phrasing** ("checked by nobody"; "not cosmetic"; "not the thing to move"). Say
  which check is missing, in which file, what it costs, and when to add it. If the point is that X
  is wrong, name what to do instead — "keep the Xcode pin and change `runs-on`", not "the Xcode pin
  is not the thing to move".
- **Metaphor or personification as the load-bearing content** ("a fresh package has no code to
  fight"; "the gate now has teeth"; "what the spec still owes"). A metaphor may decorate a point
  already stated literally; it may not be the only statement of that point. Documents do not owe,
  want, or know things — name who does the work, in which file, by when.
- **Rhetorical contrast standing in for content** ("verified, not merely committed"; "it is not that
  X, it is that Y"). State both facts separately and drop the contrast.
- **The closing paragraph that generalizes the lesson.** This is where aphorisms concentrate: a
  section ends, and the urge is to extract a portable moral. Either write a concrete rule with a
  named home — the gate to add, the file to add it to — or write nothing.

## Git state — confirm every commit

- **Never commit, amend, push or rewrite history without confirmation in the current turn.**
  "Implement X", or approval of a *previous* commit, is not authorization for the next one. When
  work is ready: stop, summarize what changed, ask.
- **Never touch the index or restore the tree.** `git add`, `git reset`, `git stash`,
  `git checkout -- <path>`: off-limits unless asked for in this turn. Staged versus unstaged is the
  reviewer's record of how far they have read, and reverting your own edits to "recover" discards
  work they have not seen. If a commit is authorized and the index is partly staged, ask which scope
  before running anything.
- **Subject line:** imperative, naming the change — "Retire the CocoaPods distribution". Work backed
  by a spec carries the slug, **and the commit that writes the spec is the first such commit**. So a
  spec numbered 002 produces:

  ```
  [002-annotation-registry-and-agent-skill] Specify the registry and the skill
  [002-annotation-registry-and-agent-skill] Route every annotation read through the registry
  [002-annotation-registry-and-agent-skill] Render the annotation table into README
  ```

  The slug names the feature and the rest names what that commit does, so the subject after the
  bracket does not repeat the slug. No spec in play, no prefix — do not invent one.

## Changes reach `master` through a pull request

- Code goes on a branch and through a PR, so [`ci.yml`](.github/workflows/ci.yml)'s five lanes run
  before it lands. They trigger on push, not on PR open.
- Any merge strategy — merge, rebase or squash — chosen for the nature of the PR.
- A change touching no code may go straight to `master`: a spec, a note, README or CHANGELOG
  wording. `templates/`, `Sources/`, `Plugins/`, `Tests/`, `Scripts/` and `.github/` are code.
- Branch when the work starts. If code is ready and the checkout is `master`, ask which branch.
- Pushing, opening a PR and merging one each need their own go-ahead.

## Specs are a read-only decision ledger

- **A merged spec is never edited** — not to fix a path a later change moved, not to correct a
  decision since superseded, not to tidy. Editing it destroys the record.
- **A new spec names what it obsoletes**, by number and section ("obsoletes 001 §4.6").
- **Writing a spec is not authorization to implement it.** When the task is a spec, produce only the
  spec document — no code, config, template or workflow edit, not even the one line that looks
  ready. When it is written, stop and ask.

## Review generated output as a snapshot diff

- **Run `Tests/Checks/run-checks.sh` before and after every template edit.** It is ~10s and it is
  the only place generated output is visible. A change that looks local to one shape routinely moves
  another.
- **Read the snapshot diff before you run `--record`.** Run the gates, read the diff they print,
  and only then `Tests/Checks/run-checks.sh --record`. Recording first overwrites the snapshot with
  whatever the template now emits, so nothing is left to compare against.
- **Never hand-edit anything in `Tests/Checks/Snapshots/`.** Those files are build products; the
  only supported way to change one is to change a template and re-record.
- **Run the full lane (`Tests/Examples/ExampleProjectSpm/test-ios.sh`) before cutting a tag**, and
  whenever a change touches RxSwift smart defaults, type erasure, or the SPM plugin — the fast lane
  covers none of those.

## State a rule once

- The isolation rules are in `templates/Mocks/SourceryRuntimeExtensions.swift`, the
  parameter-declaration rules in `MethodParameter.parametersDecl` / `closureAttributesDecl`. Both
  templates read them. Restating a rule at a call site is how the mock and the Component come to
  emit different isolation for the same protocol.
- Both language modes are the gate: `-swift-version 5 -strict-concurrency=complete` **and**
  `-swift-version 6`, at zero *diagnostics*. A construct can be a warning under the first and an
  error under the second.
- A construct the template cannot handle gets a diagnostic naming the member and what to do about
  it, not a partial emission that fails at the consumer's conformance.

## Do not tag without measuring the consumer

Follow [CONTRIBUTING.md](CONTRIBUTING.md#cutting-a-release) in order. Its most-skipped step:
regenerate `modaal-firebase-wrappers` against `master` and record the size and shape of its diff in
the `CHANGELOG.md` entry. Write that entry **before** tagging — a consumer reads it to decide
whether to bump.

## What goes in which document

- **README.md** — what the templates do and how to use them. A new annotation adds a row to its
  reference table.
- **CONTRIBUTING.md** — how the templates are built, where to change what, decided design rules,
  pitfalls, testing, release procedure, open items.
- **AGENTS.md / CLAUDE.md** — rules only, and one file in two places. If you are about to write a
  paragraph explaining what something *is*, it belongs in one of the other two.
- **specs/`NNN-slug`/spec.md** — the plan for a change too big to carry in a commit message: what is
  true now (measured, with file and line references), what the rule becomes, the phasing, the
  decisions and what stays open. Written before the change and left in place after it, as the record
  of why. It never becomes the place a *rule* is stated — that is here.

## Scope

- Generated output in a consumer repo is that repo's build product. Do not hand-edit a consumer's
  generated file to work around a template gap — fix the template and regenerate.
