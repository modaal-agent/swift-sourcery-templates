---
type: llm
focus: last_message
---
The answer gives the three `end` overloads distinct prefixes and says which rule produced them: the
overload with the fewest parameters keeps the plain name, so `end()` gives `endCallCount`, and each
other one appends its capitalized argument label — `end(at fieldValues:)` gives `endAtCallCount` and
`end(atDocument document:)` gives `endAtDocumentCallCount`.

It fails if it appends the parameter *name* as well as the label (`endAtFieldValuesCallCount`,
`endAtDocumentDocumentCallCount`), if it gives the plain name to an overload that is not the
shortest, or if it says overloads cannot be distinguished.
