---
type: llm
focus: last_message
---
The answer gives a command that prints the generated mock without compiling `Payments`, and says to
read the members from what it prints. Either of these passes:

1. the skill's `print-mocks.sh`, run from the package directory with `PaymentsTests` and
   `RefundService`;
2. `swift build --target PaymentsTests --print-manifest-job-graph`, followed by reading the
   `*.generated.swift` under `.build/plugins/outputs/…/PaymentsTests/…/.generatedFiles/`.

It fails if the way it gives to get the file is a build or a test run — `swift build`,
`swift build --build-tests`, `swift test` or `xcodebuild` — if it says the compile error has to be
fixed first, or if it lists the members from the naming rule alone without a command that reads the
generated file.
