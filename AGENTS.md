# Agent rules

Rules for working in this repository. They are the additions to
[CONTRIBUTING.md](CONTRIBUTING.md), not a summary of it.

**Read first, by question:**

| you need | read |
| --- | --- |
| what the templates generate, how to consume them, the annotation list | [README.md](README.md) |
| how the templates are built, where to change what, the pitfalls already hit | [CONTRIBUTING.md](CONTRIBUTING.md) |
| what changed in a release and what it breaks | [CHANGELOG.md](CHANGELOG.md) |
| which fixture covers which construct | [Tests/Checks/README.md](Tests/Checks/README.md) |

## The generated output is the product — review it as a diff

- **Run `Tests/Checks/run-checks.sh` before and after every template edit.** It is ~10s and it is
  the only place generated output is visible. A change that looks local to one shape routinely moves
  another.
- **`--record` is a deliberate act.** Run the gates first, read the snapshot diff, and only then
  `Tests/Checks/run-checks.sh --record`. Recording before reading turns the gate into a rubber stamp.
- **Never hand-edit anything in `Tests/Checks/Snapshots/`.** Those files are build products; the
  only supported way to change one is to change a template and re-record.
- **Run the full lane (`Tests/Examples/ExampleProjectSpm/test-ios.sh`) before cutting a tag**, and
  whenever a change touches RxSwift smart defaults, type erasure, or the SPM plugin — the fast lane
  covers none of those.

## State a rule once

- A rule about isolation lives in `templates/Mocks/SourceryRuntimeExtensions.swift`; a rule about
  parameter declarations lives in `MethodParameter.parametersDecl` /
  `closureAttributesDecl`. Both templates read them. Restating a rule at a call site is how the mock
  and the Component start disagreeing about the same protocol.
- Both language modes are the gate, not one: `-swift-version 5 -strict-concurrency=complete` **and**
  `-swift-version 6`, at zero *diagnostics*. A construct can be a warning under the first and an error
  under the second.
- A construct the template cannot handle gets a diagnostic naming the member and what to do about it,
  not a partial emission that fails at the consumer's conformance.

## Do not tag without measuring the consumer

Follow [CONTRIBUTING.md](CONTRIBUTING.md#cutting-a-release) in order. The step that gets skipped and
must not be: regenerate `modaal-firebase-wrappers` against `master` and record the size and shape of
its diff in the `CHANGELOG.md` entry. A release whose consumer impact was not measured is not ready to
tag. Write the entry **before** tagging, for a consumer deciding whether to bump.

## Keep the documents in their lanes

- **README.md** — what the templates do and how to use them. A new annotation adds a row to its
  reference table.
- **CONTRIBUTING.md** — how the templates are built, where to change what, decided design rules,
  pitfalls, testing, release procedure, open items.
- **AGENTS.md / CLAUDE.md** — rules only. If you are about to write a paragraph explaining what
  something *is*, it belongs in one of the other two.
- **specs/`NNN-slug`/spec.md** — the plan for a change too big to carry in a commit message: what is
  true now (measured, with file and line references), what the rule becomes, the phasing, the
  decisions and what stays open. A spec is written before the change and left in place after it, as
  the record of why. It never becomes the place a *rule* lives — that is still AGENTS.md.

## Scope

- Generated output in a consumer repo is that repo's build product. Do not hand-edit a consumer's
  generated file to work around a template gap — fix the template and regenerate.
