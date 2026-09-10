---
description: A generated mock missing the requirements its protocol inherits. The diagnosis is the sources list, not the annotation.
tags: [diagnosis, sources]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: The refined protocol was not among the parsed sources, so its requirements are missing from the mock; the fix is per lane.
---

The build says `type 'PaymentsMock' does not conform to protocol 'Refunding'`. `Payments` refines
`Refunding`, both are annotated, and the mock is generated — it just doesn't have the members
`Refunding` declares. What is wrong?
