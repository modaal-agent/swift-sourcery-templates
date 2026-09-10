---
type: llm
focus: last_message
---
The answer sets up generation at build time through the SwiftPM build-tool plugin, and all four of
these hold:

1. It adds the `swift-sourcery-templates` package dependency and the `SourcerySwiftCodegenPlugin`
   plugin to the `PaymentsTests` target in `Package.swift`.
2. It puts a Sourcery configuration file in the test target's own source directory, naming the
   shipped `Mocks` template.
3. The configuration sets no `output:` directory, or sets it to `${SOURCERY_OUTPUT_DIR}`.
4. It annotates the protocols to mock with `ProtocolMock` (or the legacy spelling `CreateMock`) in a
   `/// sourcery:` comment.

It fails if it tells the author to commit generated files for this package, to run a generator
script by hand, or to write the Sourcery configuration anywhere but the generating target's source
directory.
