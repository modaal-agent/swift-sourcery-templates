---
type: llm
focus: last_message
---
The answer names the cause: `Refunding` was not among the sources the generator parsed, so the
generator never saw the requirements `Payments` inherits and left them out of the mock. It is not a
missing annotation and not a template defect.

It also gives the fix for the lane in use — `- ${SOURCERY_SOURCES}` in the config's `sources:` on the
build-tool plugin lane, another `--sources` naming that module's directory on the `mock-templates`
CLI lane — or asks which lane the author is on and gives both.

It fails if it tells the author to hand-write the missing members, to add the conformance in an
extension, or to re-run the generator without changing what it parses.
