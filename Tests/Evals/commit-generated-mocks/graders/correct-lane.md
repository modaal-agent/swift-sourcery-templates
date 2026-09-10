---
type: llm
focus: last_message
---
The answer commits the generated mocks and all three of these hold:

1. It generates them with the `mock-templates` CLI — a script the repository commits, run by hand or
   in a release job — rather than with the SwiftPM build-tool plugin.
2. It gates CI with `mock-templates validate`, which re-checks the committed file against its sources
   without running the generator.
3. It says that generated mocks are `internal`, so a downstream test writes `@testable import`, or it
   otherwise addresses how the downstream package reaches them.

It fails if it recommends adding the build-tool plugin to this package as well, or if it proposes
regenerating in CI and committing the result from the job.
