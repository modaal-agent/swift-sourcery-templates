---
description: Which members a mock generates for a protocol whose names carry underscores and whose methods overload. The answer is derivable from the declarations.
tags: [naming, authoring]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: The prefix is the declared name verbatim — perform1_0CallCount, setting4_2GetCount, IDCallCount — and the overload that keeps the plain name is the one with the fewest parameters, the others taking their argument labels: endCallCount, endAtCallCount, endAtDocumentCallCount.
---

I am writing a test against a generated mock of this protocol and I do not have the generated file
in front of me. Which members does the mock give me for each requirement?

```swift
/// sourcery: ProtocolMock
protocol QueryBuilding {
    var setting4_2: Int { get set }
    var pageSize: Int { get }
    func perform1_0()
    func ID() -> String
    func end()
    func end(at fieldValues: [String])
    func end(atDocument document: String)
}
```
