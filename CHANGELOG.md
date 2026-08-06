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
