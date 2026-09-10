---
description: A protocol in a module the mock's own target does not scan. The fix is the sources list, per lane.
tags: [sources, plugin-lane, cli-lane]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: ${SOURCERY_SOURCES} in the config's sources on the plugin lane; another --sources for that module's directory on the CLI lane.
---

Mock this protocol from another module. `Refunding` is declared in `Sources/PaymentsCore`, my test
target `PaymentsTests` generates its mocks from `Sources/Payments`, and no mock is generated for
`Refunding` at all.

Tell me what to change, for the build-tool plugin and for the `mock-templates` CLI.
