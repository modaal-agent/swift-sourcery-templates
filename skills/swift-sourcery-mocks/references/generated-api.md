# The generated API, shape by shape

Every snippet below is the Swift the templates emit, copied from a generated file. It is what a test
writes against, so the names and the fallbacks here are the ones to assert on.

**The rule, in one sentence: a mock member is the declared name plus a suffix.** Verbatim, with
backticks dropped and nothing else changed: `func perform1_0()` gives `perform1_0CallCount`,
`func ID()` gives `IDCallCount`, ``func `do`()`` gives `doCallCount`, `var setting4_2: Int` gives
`setting4_2GetCount`. An overload is the one case where the name is not the declaration, below.

## The file

A generated file opens with a `// Generated using Sourcery` banner and `// DO NOT EDIT`, the imports
the parsed sources needed, and a comment block stating how members are named. Then one class per
annotated protocol:

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
| `AnyPublisher<Output, Failure>`, and the RxSwift stream types | a construct over the member's own subject — see [stream-members.md](stream-members.md) |
| `AnyCancellable` | a token that counts its own `cancel()` |
| `Disposable` | a token that counts its own `dispose()` |
| anything else | `fatalError("<method>Handler expected to be set.")` |

A method whose return type is in the last row is the one to seed before the call. `<method>CallCount`
and `<method>Args` are recorded first, so the arguments of the call that trapped are readable in the
debugger.

## Stream members

An `AnyPublisher` member hands back a construct the mock owns over a subject the test sends into and
counts what crossed it — `<name>SubscribeCount`, `<name>OutputCount`, `<name>Outputs`,
`<name>CompletionCount`, `<name>SubscribeCancelCount`; an `AnyObserver` member counts and records
what the code under test pushed in. The emitted Swift and the RxSwift shapes are in
[stream-members.md](stream-members.md).

## Properties

Every property requirement is accessors over a store named `_<var>`, and every read is counted:

```swift
var draft: String {
    get {
        draftGetCount += 1
        if let handler = draftGetHandler { return handler() }
        return _draft
    }
    set {
        draftSetCount += 1
        _draft = newValue
    }
}
var draftGetCount: Int = 0
var draftGetHandler: (() -> String)? = nil
var draftSetCount: Int = 0
var _draft: String = ""
```

`_<var>` is what a test seeds and reads without moving a counter, and for a `{ get }` requirement it
is the only way to seed one: the witness is get-only, as the requirement is, and `<var>SetCount` is
emitted for a `{ get set }` requirement only. A requirement with no synthesizable default is an
initializer parameter, keeps its name there, and seeding it at construction moves no counter.

`/// sourcery: const` makes the store a `let`, fixed at construction. `/// sourcery: handler` drops
the store: the getter runs `<var>GetHandler` and traps with that string when the test set none.

An effectful requirement generates the accessor it declares, and its handler carries the same
effects:

```swift
var config: Config {
    get async throws {
        configGetCount += 1
        if let handler = configGetHandler { return try await handler() }
        return _config
    }
}
var configGetHandler: (() async throws -> Config)? = nil
var _config: Config
```

Swift has no effectful setter, so such a requirement has no `<var>SetCount`; `_<var>` stays
assignable. A requirement declared `throws(SomeError)` fails generation naming the member: the mock
writes bare `throws`, which does not satisfy it.

Under a `@MainActor` protocol, a `nonisolated` member's store and counters are declared
`nonisolated(unsafe)`, because a nonisolated member cannot mutate main-actor isolated storage.

## Cancellation tokens

A method returning `AnyCancellable` or an RxSwift `Disposable` records the release as well as the
call. The suffix is the call the returned token exposes, so the two frameworks keep their own word:

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

A `Disposable`-returning method gets `<method>DisposeCallCount` and `<method>DisposeHandler` the same
way. The count belongs to the mock, not to the token, so it survives the token going out of scope.

## Overloads

Overloads would collide on the shared bookkeeping names, so the chain below runs over the mock's
whole requirement set — **inherited requirements included**.

1. The overload with the fewest parameters keeps the plain name.
2. Every other one appends, per parameter in declaration order, the capitalized **argument label**,
   or the capitalized parameter name where the parameter has no label.
3. If that still collides, every overload in the group takes the step-2 form plus a suffix derived
   from its return type.
4. If a collision survives step 3, generation fails naming both members.

```swift
func update(id: String)                → updateCallCount, updateArgs, updateHandler
func update(id: String, force: Bool)   → updateIdForceCallCount, …
func end(atDocument document: String)  → endAtDocumentCallCount, …   // the label, not label + name
func end(at fieldValues: [String])     → endAtCallCount, …
func putData(_ data: Data, metadata: M) → putDataDataMetadataCallCount, …   // no label: the name
```

Adding a wider overload later therefore does not rename members an existing test uses.

**The requirement set includes what the protocol inherits, so a refinement can move a name.** A
protocol declaring `func data() -> [String: Any]?` keeps `dataCallCount`; one refining it and
overriding the return type has two requirements, and both take step 3's suffix —
`dataStringAnyOptionalCallCount` and `dataStringAnyCallCount`. Neither declaration says so; the
generated file does, above the witness. `/// sourcery: methodName = "customName"` pins a name.

## What is not recorded

`<method>Args` is absent, and the call count and the handler are the whole record, when:

- every parameter is function-typed — a closure reaches the handler and stays out of the record;
- the method is generic — a stored property can only name the class's generic parameters;
- `skipArgumentRecording` is on the method, or on the protocol, which applies it to every method.

A method with no parameters gets none either. See [troubleshooting.md](troubleshooting.md).

## The same vocabulary in the Kotlin twin

A codebase that tests the same logic on both platforms gets one dialect. The Kotlin side is generated
by [kotlin-ksp-mocks](https://github.com/modaal-agent/kotlin-ksp-mocks), whose skill carries this
table with the columns the other way round.

| Swift | Kotlin |
| --- | --- |
| `<method>CallCount` | `<fn>CallCount` |
| `<method>Args` | `<fn>Args`, elements of a nested `<Fn>Args` data class rather than a tuple |
| `<method>Handler` | `<fn>Handler` |
| `<var>GetCount`, `<var>GetHandler` | `<prop>GetCount`, `<prop>GetHandler`, on every property |
| `<var>SetCount` | `<prop>SetCount`, on a `var` requirement |
| `_<var>` | `_<prop>` — the store a test seeds and reads without moving a counter, and the only way to seed a read-only requirement on either side |
| `<name>Subject` for an `AnyPublisher` member, broadcast to every subscriber | `<fn>Channel` for a `Flow` member, single-consumer |
| `<name>SubscribeCount`, `<name>SubscribeCancelCount`, `<name>OutputCount`, `<name>Outputs`, `<name>OutputHandler`, `<name>CompletionCount` | the same six, on a `Flow`-returning function or a read-only `Flow` property |
| `fatalError("<method>Handler expected to be set.")` | the same string, thrown as `IllegalStateException` |
| the initializer-seeded bag | the constructor-seeded bag |

Members with no counterpart there — the rows to check before assuming the dialects match:

| this side | Kotlin |
| --- | --- |
| a method whose `<method>Handler` supplies the publisher — its subscribe, output and completion counters stay at zero | that processor wraps a handler-supplied `Flow`, so the counters move |
| `<name>EventCallCount` / `<name>Events` / `<name>EventHandler` for an `AnyObserver` member | none — a sink-shaped requirement reaches no branch there |
| `<method>CancelCallCount`, `<method>DisposeCallCount` | none |
| the per-declaration annotations | none — that processor selects targets in the build script |

Both property getters trap with the same sentence as both method forms,
`<name>GetHandler expected to be set.` The names, the subject-backed stream shape and that string are
shared deliberately: renaming one is a change to both generators, not a local refactor.
