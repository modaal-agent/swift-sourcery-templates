# Changelog

What changed in the **generated output**, and what a consumer has to do about it.

This is a code-generation repo, so a version number by itself tells you nothing: the question a
reader has is "if I bump the tag and regenerate, what shows up in my diff, and does my project still
build?" Every entry answers that directly.

Each release lists:

- **Generated output** — what the emitted code looks like now, with before/after where the shape
  changed.
- **Breaking** — anything that can fail a consumer's build after a regenerate, with the fix.
- **Adopting** — what to do beyond bumping the tag, when there is anything.

Versions are `MAJOR.MINOR.PATCH` tags on `master`. There is no separate release branch, and the
CocoaPods distribution (`SwiftMockTemplates.podspec`) is being retired — a tag does not publish a
pod.

---

## 0.3.1 — 2026-08-06

An optional existential now generates as valid Swift. Found by the first adopter of 0.3.0
(WikiMemory: `func buildStore(… restoredSheet: (any DetailSheet)?, …)`), whose generated mock did not
compile.

### Generated output

The parser reports `(any DetailSheet)?` as `any DetailSheet?` — in `TypeName.name` *and* in
`TypeName.asSource` — and the compiler rejects `any DetailSheet?`: *"optional 'any' type must be
written '(any DetailSheet)?'"*. Every position now emits the parentheses:

```swift
// before
func present(sheet: any DetailSheet?, onDismiss: @escaping (any DetailSheet?) -> Void) -> any DetailSheet?
var restoredSheet: any DetailSheet?

// after
func present(sheet: (any DetailSheet)?, onDismiss: @escaping ((any DetailSheet)?) -> Void) -> (any DetailSheet)?
var restoredSheet: (any DetailSheet)?
```

Covered: a property, a method parameter, a return type, a handler closure's parameter and return
type, the initializer's argument list, an optional composition (`(any A & B)?`), `some` in the same
positions, and the type nested inside a closure parameter — the case a fix that only inspects the
top-level `isOptional` leaves broken. A non-optional existential is untouched, so `[any DetailSheet]`
stays as it is.

0.2.15 already carried this rule for a *stored* mock variable, inside `mockTypeName`, and nowhere
else. It now lives once, in `TypeName.parenthesizingOptionalExistentials`, and every site that emits
a type reads `declaredName` or `mockTypeName`.

### Breaking

None.

### Adopting

Bump the tag and regenerate. Measured: `modaal-firebase-wrappers` (7 modules, 33 mocks) regenerates
with **an empty diff** — no mocked signature there contains an optional existential. A consumer whose
does gets one hunk per occurrence, and a build that failed on it starts passing.

`TypeErase.swifttemplate` still emits `returnTypeName` directly and has the same gap. It is
unchanged: no consumer has hit it, and the fast lane does not generate it.

---

## 0.3.0 — 2026-08-06

A third template. `Component.swifttemplate` generates the forwarding class that satisfies a
dependency-injection protocol, for trees where each level declares an `<X>Dependency` naming exactly
what it consumes. Nothing about mock or type-erasure generation changed.

### Generated output

A protocol annotated `/// sourcery: DuetComponent` produces the class that conforms to it by
forwarding to a stored parent:

```swift
/// sourcery: DuetComponent
protocol TimelineDependency: AnyObject {
    var themeProvider: ThemeProviding { get }
    var memoryRepository: MemoryRepositoryProtocol { get }
}
```

```swift
final class TimelineComponent: TimelineDependency {
    private let dependency: TimelineDependency

    init(dependency: TimelineDependency) {
        self.dependency = dependency
    }
    var memoryRepository: MemoryRepositoryProtocol { dependency.memoryRepository }
    var themeProvider: ThemeProviding { dependency.themeProvider }
}
```

**A level that owns something** annotates `DuetComponent, owns`. A generated type cannot carry a
hand-written `lazy var`, and Swift has no stored properties in extensions, so the emission becomes a
non-`final` `<X>ComponentBase` and the level writes the subclass holding what it owns. Getting the
annotation wrong is a compile error, not a silent defect.

**What forwards:** read-only and settable requirements; `async` / `throws` / `rethrows` methods;
effectful property requirements (`{ get async throws }`); `inout`, unlabelled and differently-labelled
parameters; generic methods; `@escaping` and `@Sendable` closure parameters; requirements inherited
from a refined protocol. Isolation follows the rules 0.2.15 introduced for mocks, from the same
helpers: the protocol's global actor lands on the class, `nonisolated` is restated on the member, and
the storage becomes `nonisolated(unsafe)` where a nonisolated forwarder must read it.

**What fails generation, each with a diagnostic naming the member:** `static` requirements, `init`
requirements, `subscript` requirements, associated types. None can be discharged by forwarding to a
stored instance, so the template refuses rather than emitting a class that will not conform.

| annotation | effect |
| --- | --- |
| `DuetComponent` | generate the Component |
| `owns` | emit `<X>ComponentBase` (non-final) instead of `<X>Component` |
| `componentName = "Foo"` | name the emitted type `Foo` / `FooBase` rather than deriving it |
| `componentAccess = "public"` | emit `public`; internal is the default, whatever the protocol's access |

The emitted type is internal by default **even when the protocol is public**: a Component is consumed
by its own module's builders, and widening a module's API surface as a side effect of generating
boilerplate is not a decision a template should make.

### Breaking

Nothing. The template is additive and reads a new annotation. A repository with no `DuetComponent`
annotation generates exactly what it generated at 0.2.15 — measured on the reference consumer
(`modaal-firebase-wrappers`, 34 mocks across 7 modules): regenerated against this release, its diff is
**empty**.

### Adopting

Add a second `--templates` invocation over the same sources, writing into the module the protocols
live in (a Component is production code, not test code):

```bash
sourcery --sources Sources/MyModule \
  --templates /path/to/swift-sourcery-templates/templates/Component.swifttemplate \
  --output Sources/MyModule/Generated/Components.generated.swift \
  --args "import=Foundation"
```

Then annotate a Dependency protocol and delete its hand-written forwarders. Expect the first diff to
reorder members: generated members come out alphabetically, so introduce the regenerate-and-diff CI
step *with* the conversion rather than after it.

### Also

- **`Checks/`** now runs every template in one `TEMPLATES` list, snapshots each separately, and
  typechecks all generated files **together**. That last part is the point: a mock and a Component of
  the same protocol have to agree about which member is `nonisolated` and which class carries a global
  actor, and one compile is what checks it. 46 behaviour assertions, up from 25.
- Fixtures gained the requirement shapes forwarding has to handle
  (`Checks/Fixtures/Forwarding.swift`) and the owning-level pair
  (`Checks/Fixtures/Composition.swift`).
- CI on every push (`.github/workflows/ci.yml`): the fast `Checks/` lane, then the example project's
  simulator suite gated on it. Xcode is pinned, because the fast lane's gate is zero *diagnostics* —
  a compiler that adds one warning would fail it for a reason unrelated to the templates.

---

## 0.2.15 — 2026-08-06

Generated mocks now compile with **zero diagnostics** under `-strict-concurrency=complete` and in the
Swift 6 language mode, and Combine members are backed by a subject the test drives. Driven by a
consumer that builds with complete checking and mocks a `<X>Dependency` protocol at each of its 13
composition levels.

### Generated output

**Concurrency.** Four constructs the template used to drop:

| protocol declares | mock now gets |
| --- | --- |
| `@MainActor` (or any attribute ending in `Actor`) | the attribute on the class, so the conformance is isolated rather than inferred |
| `nonisolated func` / `nonisolated var` on an isolated protocol | `nonisolated` on the member, `nonisolated(unsafe)` on its call counter and handler |
| `func f() async throws -> T` | `func f() async throws -> T`, handler `((…) async throws -> (T))?`, `await` at the call |
| `: Sendable` | `final class …: P, @unchecked Sendable` |

Before, a `nonisolated` requirement on a `@MainActor` protocol produced a file that **did not build**
under complete checking. `async` was dropped silently: the mock compiled, because Swift permits a
less-effectful witness, but it could never suspend — so no spec could control *when* an async call
returned.

**Combine.** An `AnyPublisher<Output, Failure>` requirement is now backed by a subject:

```swift
// before — a stored property with a mandatory init parameter, undriveable
var meStream: AnyPublisher<UserSummary?, Never>
init(meStream: AnyPublisher<UserSummary?, Never>) { … }

// after
var meStream: AnyPublisher<UserSummary?, Never> { … }
lazy var meStreamSubject = CurrentValueSubject<UserSummary?, Never>(nil)
```

`CurrentValueSubject` when `Output` has a default value — a subscriber attaching after the push still
receives it, which is what a state stream needs. `PassthroughSubject` when it does not, and when
`Output` is `Void`, where a seeded subject would report every mutation as already completed. Override
per member with `/// sourcery: subject = "CurrentValue"` or `"Passthrough"`.

A method returning `AnyCancellable` now returns a token whose `cancel()` is counted
(`<method>CancelCallCount`, `<method>CancelHandler`), mirroring the RxSwift `Disposable` case. Before,
it trapped with `fatalError` unless every call site set a handler.

**`@Sendable` closure parameters** are preserved alongside `@escaping`, in the signature and in the
handler type. Dropping the attribute never broke conformance — a witness taking a non-Sendable
closure is the more general one — and it did not break capturing the closure either. What it broke
was handing the captured closure to `@Sendable`-constrained code: *"converting non-Sendable function
value to '@Sendable (Bool) -> Void' may introduce data races"*.

### Breaking

| change | what fails | fix |
| --- | --- | --- |
| mocks are `final` | subclassing a generated mock | set a handler instead |
| an `AnyPublisher` member leaves the initializer | call sites passing it to `init` | delete the argument; drive `<name>Subject` instead |
| a `@MainActor` protocol's mock is explicitly isolated | constructing it from a non-isolated context | construct it on the actor, or make the test body isolated |
| `@Sendable` restated on closure parameters | passing a non-Sendable closure to the **concrete** mock | mark the closure `@Sendable` — calling through the protocol already required it |

A mock of a **non-isolated** protocol is a non-Sendable class. Constructing it on the main actor and
then calling a nonisolated `async` member sends it across an isolation boundary, which Swift 6
rejects; drive such a mock from a non-isolated test body. This is Swift's rule, not a template
behaviour, but it surfaces the first time a consumer adopts `async` mocks.

### Adopting

Bump the tag and regenerate. In the reference consumer
(`modaal-firebase-wrappers`, 34 mocks across 7 modules) the entire diff was `class X` → `final class
X` — 34 lines, nothing else — because none of its protocols use the constructs above. Its library
targets build and its suite passes on the regenerated mocks, measured before this tag was cut.

### Also

- **`Checks/`** — a fast verification lane: generate from fixtures, diff the output against a
  recorded snapshot, typecheck under both language modes at zero diagnostics, then run 25 runtime
  assertions. No simulator, no third-party packages, ~10s. The snapshot matters on its own: generated
  output previously existed only in DerivedData, so a template change was reviewable only through its
  effect on a test.
- **`Examples/ExampleProjectSpm/test-ios.sh`** pinned `OS=26.4`, which ages out of a machine. It now
  resolves the newest installed runtime's simulator UDID; override with `DESTINATION`, `OS_VERSION`
  or `DEVICE_NAME`.
- README, CLAUDE.md and AGENTS.md document the concurrency rules, the Combine subject rule, the three
  new annotations (`globalActor`, `uncheckedSendable`, `subject`), and the two deliberate non-goals
  (member-level global actors are not propagated; mock classes are not subclassable).

---

The entries below are reconstructed from git history — they record what each tag contained, at the
level of detail the commits support.

## 0.2.14 — 2026-04-26

Overloads that share a name *and* a parameter list, differing only by return type, no longer collide.
A sanitized return-type suffix disambiguates the mock variable names (`dataStringAnyOptionalHandler`
vs `dataStringAnyHandler`). Reproducer mirrors Firebase's `QueryDocumentSnapshot : DocumentSnapshot`
shape; see `ReturnTypeOverloadMocksSpec.swift`.

## 0.2.13 — 2026-04-19

- **`@escaping` is preserved** on closure parameters, in both the method signature and the handler
  closure type. Without it a handler could not capture a completion and dispatch it later — the case
  a Combine bridge's snapshot-listener tests need.
- Sourcery bumped to **2.3.0**.
- CLAUDE.md and AGENTS.md added; README updated.

## 0.2.12 — 2025-06-20

Sourcery updated to 2.2.7.

## 0.2.11 — 2025-03-31

Compiler warning fixed.

## 0.2.10 — 2025-03-31

Updated for Xcode 16.

## 0.2.9 — 2025-01-08

Sourcery updated to 2.2.6.

## 0.2.8 — 2024-06-12

- Sourcery updated to 2.2.4.
- `inout` method parameters handled correctly.
- Properties with an `AnyObserver` return type are no longer restricted — functions behave the same.
- Optional propagation fixed for specialized "smart" return types (`Observable<T?>` and friends), and
  for an `any ProtocolType?` return type.

## 0.2.7 — 2023-12-06

Warning fixes.

## 0.2.5 – 0.2.6 — 2023-12-06

`XcodeProjectPlugin` implemented, so the templates run from an Xcode project as well as from SPM.

## 0.2.4 — 2023-12-01

`GIT_ROOT` environment variable exported to templates; trailing newline trimmed from its value.

## 0.2.2 – 0.2.3 — 2023-11-30

Prebuild-command SPM plugin.

## 0.2.1 — 2023-11-13

First tagged release of the SPM plugin distribution.
