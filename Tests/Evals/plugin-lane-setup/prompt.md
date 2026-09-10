---
description: A SwiftPM package with a test target that hand-writes its doubles. The correct lane is the build-tool plugin.
tags: [plugin-lane, setup]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: The build-tool plugin, added to the test target in Package.swift, with a config beside the test target naming the Mocks template and no `output:` key.
---

Add mock generation to this package. It has a library target `Payments` in `Sources/Payments`, a test
target `PaymentsTests` in `Tests/PaymentsTests`, and the tests hand-write their doubles today.

Reply with the changes to make. Do not make them.
