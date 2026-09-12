---
description: The members of a generated mock, asked in a SwiftPM package whose library target does not compile at the moment. The mock can be printed without a build.
tags: [plugin-lane, generated-api]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: Print the mock without compiling — the skill's scripts/print-mocks.sh with PaymentsTests and RefundService, or swift build --target PaymentsTests --print-manifest-job-graph and the file it writes under .build/plugins/outputs — and read the members from it, rather than building or fixing the compile error first.
---

`PaymentsTests` in this SwiftPM package applies `SourcerySwiftCodegenPlugin`, and its config generates
mocks for the protocols in `Sources/Payments`. I am halfway through a refactor, so `Payments` does not
compile right now. I want to start the test for `RefundService` and need the exact members
`RefundServiceMock` has; the generated file is not in the repository.

How do I see that mock?
