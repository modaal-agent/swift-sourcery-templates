# Shaping a protocol so its mock is usable

## What to annotate

Annotate the protocol the code under test depends on, not the concrete type. A mock is generated for
every protocol carrying a selector; the concrete implementation is never read.

```swift
/// sourcery: ProtocolMock
protocol MemoryRepositoryProtocol {
    var entries: AnyPublisher<[Entry], Never> { get }
    func save(_ entry: Entry) async throws
}
```

A protocol declared in a package you do not own is annotated from an empty extension in a directory
of its own, which the generation config also scans:

```swift
// SourceryAnnotations/RIBs+Mocks.swift
import RIBs

/// sourcery: ProtocolMock
extension Interactable {}
```

This keeps `/// sourcery:` comments out of API files, and it is the only way to mock a protocol
whose source is not yours to edit. Add that directory to the config's `sources:` or to a `--sources`
root.

## The shapes that generate well

- **Requirements the test drives through a closure.** Every method gets `<method>Handler` and every
  property `<name>GetHandler`, so a test controls a return value without a stub type.
- **`async` and `throws`.** Carried through to the mock method and to the handler's type, so a spec
  controls when a call returns, not only what it returns.
- **Inherited requirements.** A protocol refining another generates the refined requirements too —
  provided the refined protocol's source is among the parsed files. This is the single most common
  cause of a mock that does not conform.
- **Overloads.** Methods differing only in return type get distinct handler names.
- **Publisher and observable members.** An `AnyPublisher` member is backed by a subject the test
  sends into; the same holds for RxSwift's `Observable`, `Single` and `AnyObserver`.

## The shapes to avoid, and what to write instead

| shape | why | instead |
| --- | --- | --- |
| `static` requirements | a mock instance cannot carry them, and a Component cannot forward one | make it an instance requirement on an injected type |
| `init` requirements | the same | inject a factory closure or a builder protocol |
| `subscript` requirements | the same | a method pair |
| associated types on a protocol you want to mock | the mock would have to be generic over them | erase the type — annotate `TypeErasure` — or constrain the protocol |
| a protocol used only as a namespace | there is nothing to record | free functions, or a struct |
| effectful property requirements (`var x: T { get async throws }`) | the mock template emits a plain property, which does not satisfy the requirement | a method, `func x() async throws -> T` |

A generic method mocks, but it records no arguments: a stored property can only name the class's
generic parameters, never the method's. Assert through its handler.

## Isolation

The mock class restates the protocol's isolation:

| the protocol declares | the mock gets |
| --- | --- |
| `@MainActor`, or any attribute whose name ends in `Actor` | the same attribute on the class |
| `nonisolated func` / `nonisolated var` on an isolated protocol | `nonisolated` on the member, and `nonisolated(unsafe)` on its counter and handler |
| `: Sendable` | `final class …: P, @unchecked Sendable` — a double holds mutable counters, so the conformance cannot be checked |
| a `@Sendable` closure parameter | the attribute restated in the signature and in the handler type |
| a global actor the generator cannot name from the attribute alone | nothing — declare it with `globalActor = "MyIsolation"` |

A member-level global actor is not propagated: a non-isolated protocol whose method is `@MainActor`
produces a non-isolated mock method, which satisfies the requirement and stays callable from a
non-isolated test body.

## Components

In a dependency-injection tree where each level declares an `<X>Dependency` protocol naming exactly
what it consumes, `DuetComponent` generates the class that satisfies it by forwarding to the parent.
A level that owns something annotates `DuetComponent, owns`, which emits a non-`final`
`<X>ComponentBase` for a hand-written subclass to hold what the level owns.

Components refuse `static`, `init` and `subscript` requirements and associated types, each with a
diagnostic naming the member: none can be discharged by forwarding.

## The annotation vocabulary

<!-- annotations:start -->
<!-- Rendered from templates/Annotations/AnnotationRegistry.swift by Scripts/render-annotations.sh. Do not edit inside this block. -->

Annotation names are matched exactly, including case.

**Template selectors** — each decides whether a template generates for a type at all.

| Annotation | Target | Effect |
|------------|--------|--------|
| `ProtocolMock` | Protocol / extension | Generate the mock class |
| `ObjcProtocolMock` | Protocol / extension | Generate the mock class with an `NSObject` superclass. A protocol refining `NSObjectProtocol` gets one without the annotation |
| `TypeErasure` | Protocol | Generate the type-erasing wrapper |
| `DuetComponent` | Protocol | Generate the forwarding Component class |

**Options** — each modifies how a selected type is generated.

| Annotation | Target | Effect |
|------------|--------|--------|
| `associatedType = "T: Constraint"` | Protocol | Associated type for the type erasure |
| `genericType = "T: Constraint"` | Method | Generic type parameter |
| `annotatedGenericTypes = "{T}"` | Parameter | Generic placeholder marker |
| `methodName = "customName"` | Method | Override the mock variable name |
| `const` | Variable | Use `let` in the mock |
| `init` | Variable | Include in the mock initializer |
| `handler` | Variable | Generate the handler closure |
| `import = "Module"` | Protocol | Add an `import` to the output |
| `globalActor = "MyIsolation"` | Protocol | Declare the mock's global actor when the attribute name does not end in `Actor` |
| `uncheckedSendable` | Protocol | Force `@unchecked Sendable` on the mock when the `Sendable` refinement is not visible to Sourcery |
| `subject = "CurrentValue"` | Variable / method | Choose the subject backing an `AnyPublisher` member — `CurrentValue` or `Passthrough` |
| `skipArgumentRecording` | Protocol / method / variable | Do not generate `<method>Args`, `<name>Outputs` or `<name>Events`; counting and the handlers are unaffected |
| `owns` | Protocol | Emit `<X>ComponentBase` (non-final) for a hand-written subclass that holds what the level owns |
| `componentName = "Foo"` | Protocol | Name the emitted Component `Foo` instead of deriving it from the protocol |
| `componentAccess = "public"` | Protocol | Emit a `public` Component; the default is internal |
<!-- annotations:end -->
