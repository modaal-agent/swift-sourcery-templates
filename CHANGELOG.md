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

Versions are `MAJOR.MINOR.PATCH` tags on `master`. There is no separate release branch. The
templates are distributed through SPM and through the assets a tag publishes on its GitHub release.

---

## 0.7.0 — 2026-09-09

`validate` gains `--template <name>` and a repeatable `--args <key=value>`. Given them, it rebuilds
the `template=<basename> args=<sorted, ";"-joined>` description that `generate` and `imprint` write
into the fingerprint block and fails when it differs from the one the block records.

That closes the two generation inputs the block records and the check did not cover. Every other
field is verified against the world: the recorded input hashes against the files, the body hash
against the body, the bundle tag against `--expect-bundle`. The config line was verified against its
own SHA-256 alone — which catches a hand-edit to the line and nothing else, so a file generated with
one template or one arg list, and a config that has since moved to another, validated green.

```bash
mock-templates validate \
  --file Tests/MyModuleTests/Generated/MyModuleMocks.swift \
  --root "$(pwd)" \
  --sources Sources/MyModule \
  --expect-bundle 0.7.0 \
  --template Mocks.swifttemplate \
  --args "import=Foundation,testable=MyModule"
```

The template is recorded by basename, so a bare name and a path to the same file are one config. The
arguments are sorted into the line, so their order in a caller's config does not move it. One
definition builds the string for all three subcommands, so `generate` and `validate` cannot drift
apart on how it is spelled.

### Generated output

Unchanged. No template changed in this release, and the fast lane's snapshots are byte-identical.

### Breaking

None. Both flags are optional and a caller that passes neither gets exactly the checks 0.6.2 ran.
`--args` without `--template` is a usage error — the config line names the template first, so args
alone cannot build it.

### Adopting

Pass the two flags from whatever holds your generation config, alongside the `--sources` roots and
`--expect-bundle` tag you already pass. A file whose config moved without a regenerate turns red on
the first run; one `generate` makes it green.

## 0.6.2 — 2026-08-19

A template whose scan matches no annotated protocol now renders one marker comment instead of
nothing. The engine skips writing a whitespace-only render, so a zero-match generation previously
produced **no output file at all**. That is a problem for any pipeline that commits its generated
code and validates it in CI: the generator row cannot be registered until the first annotation
exists, and the generation step fails on the missing file until then. Now the file always exists —
the header (banner plus the row's `import=` / `testable=` lines) followed by one line:

```swift
// No protocols annotated `CreateMock` under the scanned sources.
```

(`DuetComponent` for the Component template), sitting exactly where the first type block will land.

Only the arg-less zero-match row was actually broken: a row passing `import=` or `testable=`
already rendered those lines, which is enough to make the engine write. The marker makes every
zero-match render non-whitespace, so the behaviour no longer depends on which args a row carries.

`Checks/run-checks.sh` gains a `zero-match` gate (now four): both templates generate over an
unannotated source, must write a file, and that file is snapshotted
(`Checks/Snapshots/ZeroMatch-*.generated.swift`).

### Generated output

Byte-identical for every scan that matches at least one annotated protocol. The fast lane's matched
snapshots are unchanged, and regenerating the reference consumer under 0.6.1 and under this tag
produces byte-identical output across all 7 of its generated files (34 mocks). Only the zero-match
case changes: a file where there was none.

### Breaking

Nothing. A consumer with no zero-match generator rows sees an empty diff after regenerating.

### Adopting

Bump the tag. A generator row may now be registered before its first annotation: the committed
output starts as the marker file, and the first annotation replaces it on the next generate.

## 0.6.1 — 2026-08-18

`mock-templates` excludes the file it is generating or validating from its own input set. A
generation whose `--output` lands inside one of its `--sources` roots — a Component file generated
into the module that declares it is the common case — previously recorded a self-hash that the
write immediately invalidated, so the file could never validate. Now `generate` (and `imprint`)
skip the `--output` path when enumerating inputs, `validate` skips the `--file` path in its
unlisted-file sweep, and `Checks/run-cli-checks.sh` gates the fixed point: an output written inside
its scanned root validates, its block lists no self input, and a second run over the block-bearing
tree reproduces the file byte-identically.

One rule for callers remains: when generated file A is a genuine input of generated file B (B's
roots contain A's output), generate A before B, so B records A's post-write hash.

### Generated output

Unchanged for any file whose output lies outside its scanned roots — the input list and body are
byte-identical to 0.6.0's. A self-scanned output loses one `// input:` line (itself) from its
fingerprint block; the body is unchanged.

### Breaking

Nothing. Files fingerprinted by 0.6.0 whose outputs lie outside their roots validate unchanged
under 0.6.1.

### Adopting

Bump the tag and regenerate only if a generator writes into a directory it also scans — those files
gain a valid fingerprint for the first time.

## 0.6.0 — 2026-08-18

The `mock-templates` CLI joins the package as an executable product: `generate` wraps Sourcery and
writes the output under a fingerprint block (bundle tag, generator config, path + SHA-256 of every
scanned source file, SHA-256 of the generated body), `validate` re-hashes that list with no Sourcery
run — a cold CI job proves a committed file current in seconds — and `imprint` refreshes the block
without regenerating. See README.md's "The `mock-templates` CLI" section.

Starting with this tag, a release publishes downloadable assets:
`swift-sourcery-templates-<tag>.artifactbundle.zip` carries the Sourcery engine at the pinned
version (universal macOS binary), the `templates/` tree, and the CLI — one artifact bundle whose
`info.json` declares both executables, so a SwiftPM `binaryTarget` resolves `sourcery` or
`mock-templates` by name. Beside it: `mock-templates-<tag>-macos.zip` (the CLI alone, for
`validate`-only CI lanes) and a `.sha256` for each zip. One download replaces a consumer's separate
engine download and templates clone, and the tag pins engine and templates together — there is no
pair of versions to keep matched. See README.md's "The released artifact bundle" section.

### Generated output

Unchanged: `templates/` is untouched by this release, so regenerating a consumer against it is a
diff-free no-op. A file written by `mock-templates generate` differs from a raw `sourcery` run only
by the fingerprint block above the `// Generated using Sourcery` banner; the body below the block
is byte-identical (`Checks/run-cli-checks.sh` gates this against the fast lane's snapshot).

### Breaking

Nothing. The plugin, the templates and the existing products keep their shapes. The package gains
one dependency, swift-argument-parser, resolved by consumers on their next `swift package update`.

### Adopting

Optional. A repo that commits generated mocks can switch its script's generation call to
`mock-templates generate` and its CI staleness gate to `mock-templates validate`, and its
provisioning to the released bundle — one checksum-verified download instead of an engine download
plus a templates clone.

## 0.5.0 — 2026-08-06

Every `AnyPublisher` member is backed by a `PassthroughSubject` — variable and method alike — and a
stream that replays is the test's to supply through the member's closure. This is the rule the
RxSwift members have always followed with `PublishSubject`; the Combine members were running a
second policy, and seeding made the double emit values no test wrote.

### Generated output

The seeded `CurrentValueSubject` is gone from the automatic path. Nothing else about the member
changes — the getter, the call count, the handler and the `Args` array are as they were.

```swift
protocol InviteRepositoryProtocol {
    var friends: AnyPublisher<[Connection], Never> { get }
    func getOrCreateShareLink() -> AnyPublisher<String, Error>
}
```

```swift
// before
lazy var friendsSubject = CurrentValueSubject<[Connection], Never>([])
lazy var getOrCreateShareLinkSubject = CurrentValueSubject<String, Error>("")

// after
lazy var friendsSubject = PassthroughSubject<[Connection], Never>()
lazy var getOrCreateShareLinkSubject = PassthroughSubject<String, Error>()
```

Three things followed from seeding:

1. **The double answered on subscribe** — with `""`, `[:]`, `[]` — a value no test wrote. Code that
   mapped it then failed on the empty payload, and the test read that failure as the behaviour under
   test.
2. **It answered twice.** The test's own `subject.send(realValue)` was the *second* element. A bridge
   that awaits the first value resumed its continuation twice and trapped: `SWIFT TASK CONTINUATION
   MISUSE … tried to resume its continuation more than once`.
3. **A test could not opt out by construction.** `mock.fooSubject = PassthroughSubject()` does not
   compile against a `CurrentValueSubject`-typed property.

Measured on the first consumer to hit it: 30 failing tests across 8 spec files, one suite aborted by
the continuation trap (261 tests, 250 executed). After the method half of the change: 261/0.

### Replay, when a test wants it

Through the closure the member already generates — `<name>GetHandler` on a variable,
`<name>Handler` on a method:

```swift
let state = CurrentValueSubject<UserSummary?, Never>(me)
mock.meStreamGetHandler = { state.eraseToAnyPublisher() }
```

Or at the declaration, when every test for that member wants it:
`/// sourcery: subject = "CurrentValue"`. That annotation is unchanged, works on methods as well as
variables, and still rejects an `Output` with no default value rather than downgrading silently.

### Breaking

A member whose `Output` has a default value no longer replays. A test that pushed a value **before**
the code under test subscribed now sees nothing: send after subscribing, set the member's closure to
a `CurrentValueSubject`-backed stream, or annotate the declaration.

A test that relied on a request answering by itself must state the answer — `fooSubject.send(value)`
where the server would have replied, or a `fooHandler` returning `Just(value)…` in `beforeEach` when
every row in the file wants the same one.

Any assignment of a fresh subject changes type: `CurrentValueSubject(…)` → `PassthroughSubject()`.

### Adopting

Bump the tag and regenerate. `modaal-firebase-wrappers` regenerates to an **empty diff** for this
change — it declares no `AnyPublisher` members at all.

---

## 0.4.0 — 2026-08-06

Generated mocks record their arguments. A spec that needs to know *what* a call was passed reads an
array on the mock instead of attaching a closure to the handler and accumulating into a captured
`var`.

### Generated output

One new member per mocked method with at least one recordable parameter, and one line in the method
body:

```swift
// before
func track(_ name: String) {
    trackCallCount += 1
    if let __trackHandler = self.trackHandler {
        __trackHandler(name)
    }
}
var trackCallCount: Int = 0
var trackHandler: ((_ name: String) -> ())? = nil

// after
func track(_ name: String) {
    trackCallCount += 1
    trackArgs.append(name)
    if let __trackHandler = self.trackHandler {
        __trackHandler(name)
    }
}
var trackCallCount: Int = 0
var trackArgs: [String] = []
var trackHandler: ((_ name: String) -> ())? = nil
```

What a spec wrote before, and what it writes now:

```swift
// before — a side object, wired into the handler
let tracked = ArgumentLog<AnalyticsEvent>()
analytics.trackHandler = tracked.record
XCTAssertEqual(tracked.values.first?.name, "Memory Deleted")

// after
XCTAssertEqual(analytics.trackArgs.first?.name, "Memory Deleted")
```

The element type follows the parameter list:

| the method's parameters | `<method>Args` |
| --- | --- |
| none | not generated |
| one recordable | `[T]` — Swift rejects a single-element labelled tuple, so there is nothing to label it with |
| two or more recordable | `[(first: A, second: B)]`, labelled with the parameter names, one element per call |
| a mix of recordable and closure | the recordable ones only |
| `inout T` | `[T]` — the value the caller passed in; the handler still receives the reference |

The array is a `var`, so clearing it (`mock.trackArgs = []`) is the reset. On a `nonisolated` member
of an isolated protocol it is `nonisolated(unsafe)`, for the reason the call counter is. Recording
happens before the handler runs: a handler that throws does not un-make the call.

Three things are not recorded:

- **Closure parameters.** A non-escaping closure cannot be stored at all, and storing an escaping one
  would keep the caller's captures alive for as long as the mock — which a leak or churn spec reads
  as a retain by the code under test. A spec reaches a closure through the handler, which still
  receives every parameter.
- **Generic methods.** A parameter type there names the *method's* generic parameter and a stored
  property can only name the class's, so the array would be typed against a different `S` than the
  call has. The annotated-generic mocks in `Examples/` are unchanged by this release.
- **Anything annotated `skipArgumentRecording`** (new) — on the method, or on the protocol for all of
  its methods. Call counting and the handler are unaffected. Use it for an argument whose
  deallocation a spec asserts: a recorded value lives as long as the mock.

### Breaking

None for a compiling consumer, but two name collisions are possible after a regenerate:

- A hand-written extension on a generated mock that already declares `<method>Args` collides with the
  generated one. Rename the hand-written member.
- A protocol with both a method `foo(…)` and a variable `fooArgs` produces two members of that name.
  Annotate the method `skipArgumentRecording`, or rename.

### Adopting

Bump the tag and regenerate. Nothing else is required: every existing member keeps its name, its type
and its behaviour.

Then consider what the arrays replace. For the consumer app that adopted 0.3.1 that was a
hand-written `ArgumentLog<Value>` wired into a handler in each spec; the file is deleted and its call
sites read the arrays directly.

Measured on `modaal-firebase-wrappers` (7 modules, 33 mocks): **+218 lines, 0 deletions** — 109
arrays and 109 appends, and no existing line changed. `ModaalFirebaseMocks` builds for iOS from that
diff with zero warnings, over element types the fixtures do not have: `[Any]`, `[String: Any]`,
`[String: NSObject]?` and Firestore's `Filter`.

---

## 0.3.1 — 2026-08-06

An optional existential now generates as valid Swift. Found by the first adopter of 0.3.0 — a
consumer app whose annotated protocol declares
`func buildStore(… restoredSheet: (any DetailSheet)?, …)`, and whose generated mock did not compile.

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
