---
description: A Combine test awaiting a value the mock's subject already dropped. The cause is the backing subject.
tags: [diagnosis, combine]
allowed_tools: [Read, Glob, Grep, Skill]
max_turns: 10
expected_outcome: The AnyPublisher member is backed by a PassthroughSubject, which does not replay; send after subscribing, return a CurrentValueSubject from the get handler, or annotate subject = "CurrentValue".
---

This test hangs waiting on the mock's publisher. The protocol has `var state: AnyPublisher<State,
Never> { get }`, the test sets the mock up, sends a value, and then awaits the first element — and it
never arrives.
