---
type: llm
focus: last_message
---
The answer names the cause: the generated member is backed by a `PassthroughSubject`, which delivers
nothing to a subscriber that arrives after the value was sent, so a value sent before the await is
dropped.

It gives at least two of the three fixes: subscribe before sending; return a `CurrentValueSubject`
from the generated `stateGetHandler`; annotate the requirement `subject = "CurrentValue"` so the
generated backing subject replays.

It fails if it blames the test's expectation or timeout alone, or tells the author to hand-write the
mock's publisher without naming why the generated one drops the value.
