---
type: llm
focus: last_message
---
The answer states that the bookkeeping prefix is the declared name, taken verbatim, and applies it:
`perform1_0CallCount` / `perform1_0Handler` for `perform1_0()`, `IDCallCount` / `IDHandler` for
`ID()`, and `setting4_2GetCount` / `setting4_2GetHandler` / `setting4_2SetCount` for `setting4_2`.

It fails if it lowercases, camel-cases or strips the underscore from any of them —
`perform10CallCount`, `iDCallCount` or `performCallCount` are each wrong — or if it applies one rule
to the methods and a different one to the property.
