# Stream members, shape by shape

What an `AnyPublisher` requirement and an RxSwift one generate, and which counter answers which
question. The rest of the generated API is in [generated-api.md](generated-api.md).

## A publisher member

An `AnyPublisher` requirement hands back a construct the mock owns, over a subject the test sends
into. On a property:

```swift
var ownMemories: AnyPublisher<[MemoryDrop], Never> {
    ownMemoriesGetCount += 1
    return Deferred { [weak self, subject = ownMemoriesSubject] () -> AnyPublisher<[MemoryDrop], Never> in
        self?.ownMemoriesSubscribeCount += 1
        if let handler = self?.ownMemoriesGetHandler {
            return handler()
        }
        return subject.eraseToAnyPublisher()
    }
    .handleEvents(receiveOutput: { [weak self] value in
        self?.ownMemoriesOutputCount += 1
        self?.ownMemoriesOutputs.append(value)
        self?.ownMemoriesOutputHandler?(value)
    }, receiveCompletion: { [weak self] _ in self?.ownMemoriesCompletionCount += 1 },
       receiveCancel: { [weak self] in self?.ownMemoriesSubscribeCancelCount += 1 })
    .eraseToAnyPublisher()
}
var ownMemoriesGetCount: Int = 0
var ownMemoriesGetHandler: (() -> AnyPublisher<[MemoryDrop], Never>)? = nil
var ownMemoriesSubscribeCount: Int = 0
var ownMemoriesSubscribeCancelCount: Int = 0
var ownMemoriesOutputCount: Int = 0
var ownMemoriesOutputs: [[MemoryDrop]] = []
var ownMemoriesOutputHandler: (([MemoryDrop]) -> Void)? = nil
var ownMemoriesCompletionCount: Int = 0
lazy var ownMemoriesSubject = PassthroughSubject<[MemoryDrop], Never>()
```

Four counters a test reads instead of inferring: `<var>GetCount` says the code under test asked for
the stream, `<name>SubscribeCount` that it subscribed, `<name>OutputCount` that a value reached it,
`<name>CompletionCount` that the stream ended. `<name>SubscribeCancelCount` is the cancellation.

```swift
mock.ownMemoriesSubject.send([drop])
mock.ownMemoriesSubject.send(completion: .finished)
XCTAssertEqual(mock.ownMemoriesSubscribeCount, 1)
XCTAssertEqual(mock.ownMemoriesOutputs, [[drop]])
```

**`<name>OutputCount` counts delivery, not sending.** A value sent while nobody is subscribed is
dropped by the `PassthroughSubject` and counts nothing; one sent to two subscribers counts twice.
`<name>OutputHandler` runs after the counter and the recorder, and can send the next value from
inside itself — which is how a test drives a chain without subscribing itself.

**A property's `<var>GetHandler` is read at subscribe time**, so this works:

```swift
let captured = mock.ownMemories            // the code under test holds the publisher
mock.ownMemoriesGetHandler = { Just([drop]).eraseToAnyPublisher() }
captured.sink { … }                        // the handler decides the stream
```

A method keeps `<method>Handler` at call time, where the arguments are and where the member's
`async` and `throws` apply; only the subject fallback is deferred. A handler set on a method
bypasses the subject, so `<method>SubscribeCount` stays at zero.

`/// sourcery: subject = "CurrentValue"` on the requirement makes it a `CurrentValueSubject` seeded
with the `Output`'s default value, which replays that value to a late subscriber. An `Output` with no
default value fails generation naming the member, because a `CurrentValueSubject` has to be seeded;
set `<name>GetHandler` to a stream that replays instead.

A publisher requirement declared `{ get async }` or `{ get throws }` fails generation: the closure
that reads its handler runs synchronously. Return the stream from a method instead.

An RxSwift `Observable`, `Single` or `AnyObserver` member is backed by a `PublishSubject` under the
same `<name>Subject` name and keeps its own shape. An `AnyObserver` member — a sink, where the code
under test pushes in — records what it was handed:

```swift
sut.entityObserver().onNext("next element")
XCTAssertEqual(mock.entityObserverEventCallCount, 1)
XCTAssertEqual(mock.entityObserverEvents.compactMap(\.element), ["next element"])
```

`Event` declares no `Equatable` conformance, so `<name>Events` is read through `compactMap(\.element)`,
`error` and `isCompleted` rather than compared whole. `[Output]` on the Combine side compares
directly. `/// sourcery: skipArgumentRecording` on the member or the protocol drops `<name>Outputs`
and `<name>Events`, leaving the counters and the handlers.
