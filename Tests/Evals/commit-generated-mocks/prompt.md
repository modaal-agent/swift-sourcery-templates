---
description: A library whose consumers must not run a generator. The correct lane is the CLI, with validate as the CI gate.
tags: [cli-lane, setup]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: mock-templates generate writing a committed file, and mock-templates validate in CI, rather than a build-time plugin.
---

Generate mocks and commit them so consumers don't need Sourcery. This package is a library, `Payments`,
and the mocks are used by downstream packages as well as by its own tests. CI must fail if a committed
mock stops matching the protocol it was generated from.

Reply with the changes to make. Do not make them.
