# The generated API, shape by shape

Every snippet below is the Swift the templates emit, copied from a generated file. It is what a test
writes against, so the names and the fallbacks here are the ones to assert on.

## The file

A generated file opens with a `// Generated using Sourcery` banner and `// DO NOT EDIT`, then the
imports the parsed sources needed, then one class per annotated protocol:

```swift
final class DataServiceMock: DataService {
```

The class is `final` and `internal`, named `<Protocol>Mock`, and it conforms to the protocol and
nothing else. Three variations: a `Sendable` protocol gets `, @unchecked Sendable`; a protocol
refining `NSObjectProtocol`, or one annotated `ObjcProtocolMock`, gets an `NSObject` superclass; a
`@MainActor` protocol puts `@MainActor` on the class.

Methods and properties are emitted name-sorted, whatever order the protocol declares them in, so
adding a requirement moves no other member in the diff.

## A method with one recordable parameter

```swift
func identify(uid: String) {
    identifyCallCount += 1
    identifyArgs.append(uid)
    if let __identifyHandler = self.identifyHandler {
        __identifyHandler(uid)
    }
}
var identifyCallCount: Int = 0
var identifyArgs: [String] = []
var identifyHandler: ((_ uid: String) -> ())? = nil
```

The count and the argument are recorded **before** the handler runs, so a handler that throws does
not un-make the call.

## A method with several recordable parameters

Two or more recorded parameters give one labelled tuple per call, labelled with the parameter names:

```swift
func report(_ code: String, detail: String?) {
    reportCallCount += 1
    reportArgs.append((code: code, detail: detail))
    …
}
var reportArgs: [(code: String, detail: String?)] = []
var reportHandler: ((_ code: String, _ detail: String?) -> ())? = nil
```

A test reads a field by name rather than correlating two arrays by index:

```swift
XCTAssertEqual(mock.reportArgs.last?.detail, "disk full")
```

An `inout` parameter keeps `inout` in the method and in the handler, and the recorded element type
drops it — what the mock records is the value it was handed on entry.

## `async`, `throws`, and what an unset handler returns

```swift
func upload(fileName: String) async throws -> URL {
    uploadCallCount += 1
    uploadArgs.append(fileName)
    if let __uploadHandler = self.uploadHandler {
        return try await __uploadHandler(fileName)
    }
    fatalError("uploadHandler expected to be set.")
}
var uploadHandler: ((_ fileName: String) async throws -> (URL))? = nil
```

`async` and `throws` are carried into the handler's type. What happens with no handler set:

| the return type | what an unset handler returns |
| --- | --- |
| `Void` | nothing; the handler is invoked if set and the method returns |
| any `Optional` | `nil` |
| `Array`, `Dictionary`, `Set`, a tuple of defaultable types | `[]`, `[:]`, `Set()`, the element-wise default |
| `String`, `Bool`, the integer and floating-point types, `TimeInterval`, `CGFloat`, `CGPoint`, `CGSize`, `CGRect` | `""`, `false`, `0`, `0.0`, `CGFloat(0)`, `.zero` |
| `AnyPublisher<Output, Failure>`, and the RxSwift stream types | the member's own subject, erased — see below |
| `AnyCancellable` or `Disposable` | a token that counts its own cancellation |
| anything else | `fatalError("<method>Handler expected to be set.")` |

A method whose return type is in the last row is the one to seed before the call. `<method>CallCount`
and `<method>Args` are recorded first, so the arguments of the call that trapped are readable in the
debugger.

## Publisher members

An `AnyPublisher` requirement is backed by a subject the test sends into. On a property:

```swift
var ownMemories: AnyPublisher<[MemoryDrop], Never> {
    ownMemoriesGetCount += 1
    if let handler = ownMemoriesGetHandler {
        return handler()
    }
    return ownMemoriesSubject.eraseToAnyPublisher()
}
var ownMemoriesGetCount: Int = 0
var ownMemoriesGetHandler: (() -> AnyPublisher<[MemoryDrop], Never>)? = nil
lazy var ownMemoriesSubject = PassthroughSubject<[MemoryDrop], Never>()
```

On a method the same subject sits behind `<method>Handler`, as `<method>Subject`. The default is a
`PassthroughSubject`, which delivers nothing to a subscriber that arrives after the value was sent,
and the erased publisher finishes only when the test sends a completion:

```swift
mock.ownMemoriesSubject.send([drop])
mock.ownMemoriesSubject.send(completion: .finished)
```

`/// sourcery: subject = "CurrentValue"` on the requirement makes it a `CurrentValueSubject` seeded
with the `Output`'s default value, which replays that value to a late subscriber. An `Output` with no
default value fails generation naming the member, because a `CurrentValueSubject` has to be seeded;
set `<name>GetHandler` to a stream that replays instead.

An RxSwift `Observable`, `Single` or `AnyObserver` member takes the same shape, backed by a
`PublishSubject` under the same `<name>Subject` name.

## Properties

```swift
// var requirement: stored, and writes are counted. Construction does not count.
var draft: String = "" {
    didSet {
        draftSetCount += 1
    }
}
var draftSetCount: Int = 0

// read-only requirement with a default value: a var a test can re-seed.
var identifier: String = ""

// read-only requirement without one: a stored property and an initializer parameter.
var analytics: AnalyticsTracking
init(analytics: AnalyticsTracking, memoryRepository: MemoryRepositoryProtocol) { … }
```

There is no `<var>GetCount` for a stored property — a read of a stored `var` is not counted; the
counted form is the computed one publisher members and effectful requirements take. A protocol of
properties alone therefore generates an initializer-seeded bag, and adding a requirement without a
default value to it breaks every construction of the mock at compile time.

Under a `@MainActor` protocol, a `nonisolated` member's storage is declared `nonisolated(unsafe)`,
because a nonisolated member cannot mutate main-actor isolated storage.

## Cancellation tokens

A method returning `AnyCancellable` or an RxSwift `Disposable` records the cancellation as well as
the call:

```swift
func registerURLHandler(_ tag: String, priority: Int) -> AnyCancellable {
    …
    return AnyCancellable { [weak self] in
        self?.registerURLHandlerCancelCallCount += 1
        self?.registerURLHandlerCancelHandler?()
    }
}
var registerURLHandlerCancelCallCount: Int = 0
var registerURLHandlerCancelHandler: (() -> ())? = nil
```

A test asserts that the caller released the registration by reading `<method>CancelCallCount`. The
count belongs to the mock, not to the token, so it survives the token going out of scope.

## Overloads

Overloads would collide on the shared bookkeeping names. The overload with the fewest parameters
keeps the plain name; each other overload appends its parameter labels and names, capitalized:

```swift
func update(id: String)                → updateCallCount, updateArgs, updateHandler
func update(id: String, force: Bool)   → updateIdForceCallCount, updateIdForceArgs, updateIdForceHandler
```

Adding a wider overload later therefore does not rename the members an existing test already uses.
Two overloads with the same number of parameters take the long form on both sides, and overloads
differing only in return type get a suffix derived from that type. `methodName = "customName"` on a
method names its members outright.

## What is not recorded

`<method>Args` is absent, and the call count and the handler are the whole record, when:

- every parameter is function-typed — a closure reaches the handler and stays out of the record;
- the method is generic — a stored property can only name the class's generic parameters;
- `skipArgumentRecording` is on the method, or on the protocol, which applies it to every method.

A method with no parameters gets no `<method>Args` either. Symptoms and fixes are in
[troubleshooting.md](troubleshooting.md).

## The same vocabulary in the Kotlin twin

A codebase that tests the same logic on both platforms gets one dialect. The Kotlin side is generated
by [kotlin-ksp-mocks](https://github.com/modaal-agent/kotlin-ksp-mocks), whose skill carries this
table with the columns the other way round.

| Swift | Kotlin |
| --- | --- |
| `<method>CallCount` | `<fn>CallCount` |
| `<method>Args` | `<fn>Args`, elements of a nested `<Fn>Args` data class rather than a tuple |
| `<method>Handler` | `<fn>Handler` |
| `<var>GetCount`, `<var>GetHandler` | `<prop>GetCount`, `<prop>GetHandler` |
| `<var>SetCount` | `<prop>SetCount` |
| `<method>Subject` for an `AnyPublisher` member | `<fn>Channel` for a `Flow` member |
| `fatalError("<method>Handler expected to be set.")` | the same string, thrown as `IllegalStateException` |
| the initializer-seeded bag | the constructor-seeded bag |

Members with no counterpart there: `<method>CancelCallCount`, and the per-declaration annotations of
this generator, which that processor has no equivalent for because it selects targets in the build
script. The property getter that traps is spelled differently on this side — `` `<var>GetHandler`
must be set! `` — where the method form matches Kotlin's string exactly.

The names, the subject-backed stream shape and the handler-expected string are shared deliberately.
Renaming one of them is a change to both generators, not a local refactor.
