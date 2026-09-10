---
type: llm
focus: last_message
---
The answer gives both lanes, and all three of these hold:

1. On the build-tool plugin lane it puts `- ${SOURCERY_SOURCES}` in the config's `sources:` list, and
   says that the placeholder expands to the target's dependencies as well as its own sources.
2. On the CLI lane it adds another `--sources` argument naming `Sources/PaymentsCore`.
3. It says that `Refunding` has to carry a `ProtocolMock` annotation — written on the declaration, or,
   if the module is not the author's to edit, on an empty `extension Refunding {}` in a directory the
   configuration also scans.

It fails if it tells the author to copy the protocol, to hand-write the mock, or to pass sources on
the Sourcery command line beside a `--config` file.
