# Claude Code Instructions

The rules for working in this repository are in [AGENTS.md](AGENTS.md). Read it before editing
anything under `templates/`.

They are deliberately in one file rather than two: this repository previously carried the same
material in `AGENTS.md` and `CLAUDE.md`, and the copies drifted.

Where the rest lives:

| you need | read |
| --- | --- |
| what the templates generate, how to consume them, the annotation list | [README.md](README.md) |
| how the templates are built, where to change what, the pitfalls already hit | [CONTRIBUTING.md](CONTRIBUTING.md) |
| what changed in a release and what it breaks | [CHANGELOG.md](CHANGELOG.md) |
| which fixture covers which construct | [Checks/README.md](Checks/README.md) |
| the plan for a change too big to carry in a commit message | [specs/](specs/) |

The two commands worth memorising:

```bash
Checks/run-checks.sh              # ~10s — snapshot, both language modes, behaviour
Checks/run-checks.sh --record     # only after reading the diff the line above printed
```
