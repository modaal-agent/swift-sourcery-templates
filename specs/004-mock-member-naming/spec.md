# 004 — One naming rule for generated mock members

**Status:** Proposed. Nothing here is implemented. §2 states the rule this proposes, §3 records each
decision with the options considered and a recommendation, §4 phases the work. The phases are
separable: P1 changes no output, P2 is the change the measurements below argue for, and P3–P4 are
consolidations that can be dropped without affecting P2.

**Measurements:** every number, path and quoted string in §1 was produced on 2026-09-11 against
`master` at `8034c2b`, using working copies present on this machine: the eval lab
(`/Volumes/DATA01/Projects/modaal-agent-devto-mock-generation-lab`), its run root
(`/Volumes/DATA01/mock-lab`), `kotlin-ksp-mocks` and `modaal-firebase-wrappers`. Nothing in any
repository was changed to take them; the two transform measurements in §1.2 were taken by copying
the function under test into a standalone file in the session scratchpad and compiling it.

**Scope of the change:** `templates/Mocks/MockMethod.swift`, `templates/Mocks/MockVar.swift`,
`templates/Mocks/MockGenerator.swift`, `templates/Mocks/SourceryRuntimeExtensions.swift`,
`templates/Utility/StringLettercase.swift`, the fixtures and snapshots under `Tests/Checks/`, the
specs under `Tests/Examples/ExampleProjectSpm/`, `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`,
`AGENTS.md`/`CLAUDE.md` and `skills/swift-sourcery-mocks/`. It is a breaking change to generated
output. Outside this repository it touches `modaal-firebase-wrappers` (the regenerate in §5) and one
paragraph of `kotlin-ksp-mocks/skills/kotlin-ksp-mocks/references/generated-api.md` (§4, P5).

**Not in scope:** an annotation-registry-style declaration file with a CI job checking three sources
for drift. Member naming stays gated by the snapshot diff and by review while the rule is being
iterated on; §3 D7 records the deferred option.

**Obsoletes:** nothing.

**Follows:** 003 §4 option 1 (bump `modaal-firebase-wrappers` and commit its regenerated output).
That bump is required by this change rather than optional, and §5 states how the two combine.

---

## 0. TL;DR

1. A mocked **method**'s bookkeeping prefix is rewritten before use — backticks stripped, `(` and
   `:` turned into `_`, then camel-cased and first-word-lowercased (`MockMethod.swift:50-62`,
   `:254-261`). A mocked **property**'s prefix is the declared name, unchanged
   (`MockVar.swift:8-10`). Both appear in one generated class: `stream3_4()` produces
   `stream34Subject` beside `updates1_1` producing `updates1_1Subject` (§1.1).
2. The method transform is many-to-one and can trap. `perform1_0`, `perform10` and `perform_1_0` all
   produce `perform10`; an all-uppercase method name (`func URL()`) aborts generation with
   `Fatal error: String index is out of bounds` (§1.2).
3. An overloaded method appends the capitalized argument label **and** the capitalized parameter
   name for every parameter, so `func end(atDocument document:)` produces `endAtDocumentDocument`
   and `func reference(withPath path:)` produces `referenceWithPathPath` (§1.3).
4. The same declaration produces different names in different mocks: `func data() -> [String: Any]?`
   is `dataCallCount` in `DocumentSnapshotProtocolMock` and `dataStringAnyOptionalCallCount` in
   `QueryDocumentSnapshotProtocolMock` (§1.4).
5. In one lab run an agent wrote `perform3_0CallCount` — the declared name — and
   `load9_0ReturnValue` — a suffix from another generator's dialect — and the build named both
   (§1.5).
6. Nothing states the derivation rule. `SKILL.md`'s member table writes `<method>` and `<var>`
   without saying how either is derived; the overload rule is in `references/generated-api.md` only,
   which a `--restricted` eval arm cannot open (§1.7). `SKILL.md:202` also states a member name the
   templates do not emit (§1.7).
7. Member names are composed at 32 sites across three template files (§1.8).
8. A stored property requirement generates no read counter: `<var>GetCount` exists only where the
   getter is already computed (`MockVar.swift:64-118`). The Kotlin processor has the same gap
   (`MockRenderer.kt:127-140`), and a lab run planned 20 test cases against a `value6_0GetCount`
   that does not exist before re-reading and replanning
   (`findings/what-the-runs-said-about-the-work.md` §2).
9. Nothing checks that a property's generated names are unique: `MockMethod.from` guards methods
   (`MockMethod.swift:24-26`) and `MockVar.from` guards nothing (`MockVar.swift:17-20`), so a
   protocol declaring both `draft` and `draftGetCount` emits the same declaration twice and the
   generated file does not compile (§3 D9).
10. **The rule this proposes:** the prefix is the declared name with backticks removed, for a method
    and a property alike; an overloaded method appends its selector's labels; every property
    requirement carries `GetCount`, `GetHandler`, a `_<var>` store and — when settable — `SetCount`;
    an effectful requirement carries the accessor it declares; a publisher member hands back a
    `Deferred` the mock owns, counting subscriptions, cancellations, values delivered and
    completions, with `<name>OutputHandler` and `<name>Outputs` beside the values, and an
    `AnyObserver` member records `<name>Events` the way a method records `<method>Args`; every
    emitted name goes through one uniqueness check; and the suffix set is fixed and lives in one
    file (§2).

---

## 1. Measured

### 1.1 Two transforms in one generated class

`MockMethod.swift:50-62` builds a method's prefix and ends with `.swiftifiedMethodName`
(`MockMethod.swift:254-261`), which replaces `(` with `_`, drops `)`, replaces `:` with `_`, drops
backticks, calls `camelCased()` (`templates/Utility/StringLettercase.swift:86-110`) and then
`lowercasedFirstWord()` (`:37-50`). `camelCased()` splits on `_` and capitalizes each component, so
the underscores are removed.

`MockVar.swift:8-10` returns `variable.name` with no transform.

Measured on the mock generated inside lab run `swift-G-r3-10x2-s1-20260911-155532`
(`work/tree/.build/plugins/outputs/tree/PaymentsServiceTests/destination/SourcerySwiftCodegenPlugin/.generatedFiles/Sourcery.Mocks/Mocks.generated.swift`),
whose protocols are at `work/tree/Sources/PaymentsKit/Protocols.swift`: **19 of 19 declared methods
produce a prefix that differs from the declared name**, and every property prefix is the declared
name.

| declared | generated |
| --- | --- |
| `func perform1_0()` | `perform10CallCount`, `perform10Handler` |
| `func load1_4(id:)` | `load14CallCount`, `load14Args`, `load14Handler` |
| `func stream3_4() -> AnyPublisher<String, Never>` | `stream34CallCount`, `stream34Subject` |
| `var setting4_2: Int { get set }` | `setting4_2SetCount` |
| `var updates1_1: AnyPublisher<String, Never> { get }` | `updates1_1GetCount`, `updates1_1Subject` |

The last two rows and the third are in the same generated file: a stream declared as a method loses
its underscore, a stream declared as a property keeps it.

### 1.2 The method transform is many-to-one, and one input traps

`swiftifiedMethodName` maps distinct declarations onto one prefix. Measured by compiling
`StringLettercase.swift`'s `snakeToCamelCase` and `lowerFirstWord` verbatim into a standalone file
and running the pipeline over a list of inputs:

| input | output |
| --- | --- |
| `perform1_0` | `perform10` |
| `perform10` | `perform10` |
| `snake_case_name` | `snakeCaseName` |
| `_private` | `_Private` |
| `URLFor` | `urlFor` |
| `HTTPGet` | `httpGet` |
| `` `do` `` | `do` |

Two methods whose names differ only by underscore placement therefore collide. The collision is
caught: `MockMethod.from` (`MockMethod.swift:24-26`) throws `MockError.internalError` when
duplicates survive disambiguation. Its message is
`"Mock generator: not all duplicates resolved: \(mockedMethods.map { $0.mockedMethodName })"`, which
lists every mocked name in the type and names no action. §2.2 step 4 states what it names instead.

**An all-uppercase method name aborts generation.** `lowerFirstWord`'s loop
(`StringLettercase.swift:39-43`) indexes `scalars[idx]` before testing `idx` against
`scalars.endIndex`, so a string of uppercase scalars runs off the end. Measured by compiling that
function verbatim (`swiftc -Onone`) and calling it with `"URL"`:

```
Swift/StringIndexValidation.swift:121: Fatal error: String index is out of bounds
```

`func URL()` and `func ID()` are legal Swift protocol requirements. No fixture under
`Tests/Checks/Fixtures/` and no protocol in `Tests/Examples/` declares one, so no lane covers this.
The property path never calls the transform, so a property named `URL` generates.

### 1.3 An overloaded method carries the label and the parameter name

`MockMethod.swift:53-59` appends, per parameter: the capitalized argument label when the label is
present **and** differs from the parameter name, then the capitalized parameter name.

Measured in `modaal-firebase-wrappers`'s committed output (generated at templates 0.2.15, pinned at
`scripts/generate-mocks.sh:9`):

| declaration | emitted prefix |
| --- | --- |
| `func end(atDocument document: DocumentSnapshotProtocol)` (`Sources/ModaalFirestore/Protocols/QueryProtocol.swift:15`) | `endAtDocumentDocument` |
| `func end(at fieldValues: [Any])` (`:21`) | `endAtFieldValues` |
| `func reference(withPath path: String)` (`Sources/ModaalCloudStorage/Protocols/CloudStorageProtocol.swift:9`) | `referenceWithPathPath` |
| `func reference(forURL url: String)` (`:8`) | `referenceForURLUrl` |
| `func document(_ path: String)` | `documentPath` (`ModaalFirestoreMocks.swift:63-71`) |

The selector a Swift reader writes for the first row is `end(atDocument:)`. The prefix repeats the
label's last word as the parameter's name.

### 1.4 One declaration, two names, decided by the rest of the mock

`MockMethod.from` gives the plain prefix to the overload with the fewest parameters
(`MockMethod.swift:395-434`) and falls back to a return-type-derived suffix when long names still
collide (`:436-450`, `:277-300`). The requirement set includes inherited requirements, so a refining
protocol changes the names of members it does not declare.

In `modaal-firebase-wrappers/Sources/ModaalFirebaseMocks/Generated/ModaalFirestoreMocks.swift`:

- `DocumentSnapshotProtocolMock` (`:305`) — `var dataCallCount` (`:327`), from
  `func data() -> [String: Any]?`.
- `QueryDocumentSnapshotProtocolMock` (`:405`), which refines it and adds
  `func data() -> [String: Any]` — `var dataStringAnyCallCount` (`:427`) and
  `var dataStringAnyOptionalCallCount` (`:436`).

Across that repository's 7 generated files there are **107 distinct `<method>CallCount` prefixes
over 152 emitted call counters, and 28 of the 107 are not equal to any `func` name declared anywhere
in the repository** — that is, 26% of the method vocabulary cannot be read off a declaration's name
at all.

### 1.5 What this costs a run

`RESULTS.md` §"Round 3 on three models" ¶2 reports G ÷ H in dollars: Swift 1.30 / 1.44 / **2.80**
for `opus-5` / `sonnet-5` / `haiku-4.5`, Kotlin 1.48 / 1.00 / 0.96. The Swift generator arm on
`haiku-4.5` took 41 turns, 7 builds and the only 2 build errors in that sweep, against sonnet's
21/3/0 and opus's 14/3/0.

One transcript carries the naming failure directly. In
`/Volumes/DATA01/mock-lab/swift-G-r3-10x2-s1-20260911-182818/sessions/session.jsonl`:

```
error: value of type 'Dep3ServiceMock' has no member 'perform3_0CallCount'
error: value of type 'Dep9ServiceMock' has no member 'load9_0ReturnValue'
```

The first is the declared name (`perform3_0`), which the generator had emitted as `perform30`. The
second is a suffix (`ReturnValue`) from another Swift mock generator's vocabulary. No other
`swift-*` run in that root wrote a member name the compiler rejected.

The nearest Kotlin equivalent, in `kotlin-G-r3-10x2-s1-20260911-183602`, is
`No parameter with name 'value4_0' found.` — the run spelled the member the way the interface
declares it and was wrong about **which** members exist (a constructor-seeded property), not about
how a name is spelled.

`findings/what-the-runs-said-about-the-work.md` §2 records what both generator arms asked for when
asked for one thing that would have made the job faster: the naming rule, stated where they would
see it.

### 1.6 What the Kotlin processor does

`kotlin-ksp-mocks/mocks-processor/src/main/kotlin/dev/modaal/mocks/MockRenderer.kt`:

- the prefix is the declared name, used verbatim (`:169`, `:191`, and `renderProperty` at `:105`);
- an overload group is ordered by parameter count, the first keeps the plain name, the others append
  their capitalized parameter names (`:83-97`);
- a residual collision is a hard error naming the collisions (`:99-102`).

Kotlin has no argument labels, so `update(id:force:)` → `updateIdForce` is the same on both sides
today. The transform in §1.1 has no counterpart there.

### 1.7 Where the rule is stated, and one place it is stated wrongly

- `skills/swift-sourcery-mocks/SKILL.md:195-202` lists the suffixes against `<method>` and `<var>`
  and never says how `<method>` or `<var>` is derived from a declaration.
- The overload rule appears once, in `skills/swift-sourcery-mocks/references/generated-api.md`
  §"Overloads". `Tests/Evals/README.md` records that under `--restricted` the with-skill arm cannot
  open `references/*.md`, so a case run that way is answered from `SKILL.md` alone.
- `README.md` §"Generated Mock API" and §"Recorded arguments" show the suffixes on worked examples
  and state no derivation rule either.
- No document in this repository or in the skill tree mentions the transform in §1.1.
- `SKILL.md:202` reads: `` | `<method>CancelCallCount` | for a method returning `AnyCancellable` or
  a `Disposable`: how many times the returned token was cancelled | ``. For `Disposable` the
  templates emit `<method>DisposeCallCount` and `<method>DisposeHandler`
  (`SourceryRuntimeExtensions.swift:431-436`). The documented name does not exist.

A lab run did read the reference file and still read the generated output:
`swift-G-r3-10x2-s1-20260911-181640` runs
`sed -n 1,200p .claude/skills/swift-sourcery-mocks/references/generated-api.md`, then locates and
prints `Mocks.generated.swift`.

### 1.8 Where the names are built

A member name is composed by interpolating a prefix with a suffix literal at **32 sites in three
files**: `MockMethod.swift` 3 (through `mockedVarCallCountName` `:156-158`, `mockedVarArgsName`
`:164-166`, `mockMethodHandlerName` `:210-212`), `MockVar.swift` 11 (`:73-113`),
`SourceryRuntimeExtensions.swift` 18 (`:326-352`, `:398-436`). The two `fatalError` strings are
written at `MockMethod.swift:146` and `MockVar.swift:91`, in different words:

```swift
methodImpl += "fatalError(\"\(mockHandler.0) expected to be set.\")"          // MockMethod.swift:146
SourceCode("fatalError(\"`\(mockedVariableName)GetHandler` must be set!\")")  // MockVar.swift:91
```

`kotlin-ksp-mocks/skills/kotlin-ksp-mocks/references/generated-api.md` §"The same vocabulary in the
Swift twin" records the divergence as a fact about this repository.

### 1.9 What a consumer's tests assert on

`/Volumes/DATA01/Projects/popapp/Apps/FabFun` generates mocks through the SPM plugin across 43 spec
files. Its `Package.swift` files pin `from: "0.2.11"` and `Package.resolved` holds 0.2.11 exactly,
so these mocks predate argument recording, which landed in 0.4.0 (`629a28e`, "Record the arguments
of every mocked call"). Counted over those spec files:

| what the test writes | references |
| --- | ---: |
| `<name>CallCount` | 84 |
| `<name>Subject.onNext(…)` — driving a stream the mock exposes | 17 |
| `<var>GetHandler = { Observable.just(…) }` — supplying a stream | 13 |
| `<name>EventCallCount` | 1 |
| `<name>EventHandler = { … }` | **0** |
| `<name>Args` | 0 — the version has none |

The single `AnyObserver` assertion is `LessonInteractorSpec.swift:220`,
`expect(presenter.lessonObserverEventCallCount) == 1`, while the code under test pushes a particular
value: `LessonInteractor.swift:173`, `presenter.lessonObserver().onNext(lesson)`. Asserting *which*
lesson would take a handler that appends into a local array, and no spec file in the repository does
that for any member.

`modaal-agent-duet-services`, whose mocks do carry argument recording, inverts the ratio: **15
`Args` references against 2 `CallCount`**, and they assert both what crossed and what did not —
`XCTAssertEqual(high.handleOpenUrlArgs, [url])` and
`XCTAssertEqual(catchAll.handleOpenUrlArgs, [], "a pre-settle event must not dispatch")`
(`swift/Tests/ServicesTests/InboundAppServicesWorkerTests.swift:38`, `:102`).

Where a recorder exists, tests assert on the recorded values. Where a counter and an observing
handler exist, they assert the count and leave the value untested.

---

## 2. The rule this proposes

### 2.1 The prefix is the declared name

For every mocked member — method and property alike — the bookkeeping prefix is the member's
declared name with backticks removed, and nothing else: no case change, no underscore removal, no
first-word lowercasing.

| declared | prefix |
| --- | --- |
| `func perform1_0()` | `perform1_0` |
| `var setting4_2: Int { get set }` | `setting4_2` |
| `func ID() -> String` | `ID` |
| ``func `do`()`` | `do` |

Stated for a reader in one sentence: **a mock member is the declared name plus the suffix.**

This removes the transform at `MockMethod.swift:254-261`, the many-to-one mapping in §1.2 and the
trap in §1.2, and makes the Swift prefix rule the same sentence as the Kotlin one (§1.6).

### 2.2 An overloaded method appends its selector's labels

When two or more requirements of the mock's full requirement set — inherited requirements included —
share a base name, the chain is:

1. The overload with the fewest parameters keeps the plain prefix. Between two with the same count,
   the one whose first parameter has no argument label keeps it (`MockMethod.swift:412-422`,
   unchanged).
2. Every other overload appends, per parameter in declaration order, the capitalized **argument
   label**, or the capitalized parameter name when the label is `_`.
3. If step 2 leaves a collision, every overload in the group takes the form in step 2 and a suffix
   derived from the return type is appended (`MockMethod.swift:277-300`, unchanged).
4. If a collision survives step 3, generation fails naming the colliding members and
   `/// sourcery: methodName = "customName"`.

Step 2 is the change: today the label **and** the parameter name are both appended when they differ.

| declaration | today | proposed |
| --- | --- | --- |
| `func end(atDocument document:)` | `endAtDocumentDocument` | `endAtDocument` |
| `func end(at fieldValues:)` | `endAtFieldValues` | `endAt` |
| `func reference(withPath path:)` | `referenceWithPathPath` | `referenceWithPath` |
| `func update(id:force:)` | `updateIdForce` | `updateIdForce` |
| `func putData(_ data:metadata:completion:)` | `putDataDataMetadataCompletion` | `putDataDataMetadataCompletion` |

The last two rows are the Kotlin-comparable case (label equal to name, or absent), and they do not
move.

### 2.3 One suffix set

| suffix | on | emitted when |
| --- | --- | --- |
| `CallCount` | method | always |
| `Args` | method | at least one recordable parameter (`CONTRIBUTING.md` §"Design rules already decided") |
| `Handler` | method | always |
| `GetCount`, `GetHandler` | property | always (§2.5) |
| `SetCount` | property | the requirement is `{ get set }` |
| `_` prefix | property | `_<var>` is the stored value a test seeds or reads without moving a counter (§2.5) |
| `Subject` | method, property | `AnyPublisher`, `Observable`, `Single` |
| `SubscribeCount` | method, property | the type is `AnyPublisher` — the code under test subscribed (§2.7) |
| `SubscribeCancelCount` | method, property | the type is `AnyPublisher` — it cancelled (§2.7) |
| `OutputCount`, `OutputHandler`, `Outputs` | method, property | the type is `AnyPublisher` — values the member **delivered**: counted, handed to the handler, recorded (§2.7) |
| `CompletionCount` | method, property | the type is `AnyPublisher` — the stream finished or failed (§2.7) |
| `CancelCallCount`, `CancelHandler` | method | the return type is `AnyCancellable` |
| `DisposeCallCount`, `DisposeHandler` | method | the return type is `Disposable` |
| `EventCallCount`, `EventHandler`, `Events` | method, property | the type is `AnyObserver` — events pushed **in**: counted, handed to the handler, recorded (§2.7) |

A returned token's suffix is the name of the call that token exposes: `cancel()` on `AnyCancellable`
gives `Cancel*`, `dispose()` on RxSwift's `Disposable` gives `Dispose*`. Both stay (D4), and
`SKILL.md:202` — which documents `<method>CancelCallCount` for either return type — states each
against its own (§1.7).

**A counter gets a handler where the shape being mirrored has one** (D12). Which have one, and why:
`<method>CallCount`/`<method>Handler` and `<var>GetCount`/`<var>GetHandler`, the member's own, which
**supply** what it returns; `<name>EventCallCount`/`<name>EventHandler` and
`<name>OutputCount`/`<name>OutputHandler`, the payload crossing the member — pushed in on an
`AnyObserver`, delivered out on an `AnyPublisher`; and `<name>CancelCallCount`/`<name>CancelHandler`
with `<name>DisposeCallCount`/`<name>DisposeHandler`, the token the mock built being released. The
rest are counters alone: `<var>SetCount`, `<name>SubscribeCount`, `<name>SubscribeCancelCount` and
`<name>CompletionCount`. A handler beside a counter **observes** and returns nothing, which is what
separates it from the two that supply.

**What crosses a stream member is recorded, the way a method's arguments are** (D13). `<method>Args`
has no counterpart on a stream member today, so a test that wants the value rather than the count
writes a handler that appends into an array of its own — measured at zero occurrences across a
43-spec consumer (§1.9). `<name>Events: [Event<Element>]` on an `AnyObserver` member and
`<name>Outputs: [Output]` on an `AnyPublisher` one close that gap. Both are appended before the
handler runs, both sit under the existing `skipArgumentRecording` opt-out, and for the same reason a
method's arguments do: a recorded value lives as long as the mock. RxSwift's `Event` declares no
`Equatable` conformance — `RxSwift/Sources/RxSwift/Event.swift:13-101` carries
`CustomDebugStringConvertible` and `EventConvertible` and nothing else — so the value idiom on that
side is `mock.<name>Events.compactMap(\.element)`, with `error` and `isCompleted` for the terminal
ones; `[Output]` on the Combine side compares directly.

`EventCallCount` counts calls of `on(_:)` on the `AnyObserver` the member handed back:
`sut.entityObserver().onNext("next element")` moves `entityObserverEventCallCount`, while
`entityObserverCallCount` counts the calls that produced the observer
(`Tests/Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/SwiftSourceryTemplatesMocksSpec.swift:48-55`).
It is emitted for a property requirement as well as a method one — `Protocols.swift:19` in that
example declares `var bindingTarget: AnyObserver<UploadAPI.LocalFile> { get }`, and `MockVar`
reaches the same branch (`MockVar.swift:51-62`, `SourceryRuntimeExtensions.swift:345-354`). An
`AnyPublisher` member runs the opposite direction — the mock produces and the test drives
`<name>Subject` — so it has no delivery from the code under test to count. §8 question 4 carries
what could be counted there instead.

### 2.4 Two diagnostics, one wording

| condition | text |
| --- | --- |
| a method with no handler and no defaultable return | `<prefix>Handler expected to be set.` |
| a `handler`-annotated property read with no handler | `<prefix>GetHandler expected to be set.` |
| overload names still colliding after §2.2 step 3 | names each colliding member and `methodName = "…"` |

The second replaces `` `<prefix>GetHandler` must be set! `` (`MockVar.swift:91`). The first is
already the string `kotlin-ksp-mocks` matches byte for byte.

### 2.5 Every property requirement is counted

A stored property is emitted today as storage with a `didSet` (`MockVar.swift:64-118`), so a read
cannot be observed and `<var>GetCount` exists only where the getter is already computed — a stream
member or one annotated `/// sourcery: handler`. Under this rule every property requirement
generates the same members, and the value moves to a backing store named `_<var>`:

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

Six rules the shape carries:

- **Construction counts no set.** The generated initializer assigns `_<var>`
  (`MockGenerator.swift:69-77` assigns `<var>` today) and keeps its argument label `<var>`, so a
  consumer's `Mock(analytics:)` call is unchanged and `README.md` §"Generated Mock API"'s statement
  stays true once the property is computed.
- **A test seeds and reads through `_<var>`** when it does not want to move a counter. Assigning
  `mock.draft` moves `SetCount` today and will move it after this change too; reading `mock.draft`
  starts moving `GetCount`.
- **`/// sourcery: const` keeps its meaning on the value:** the storage is a `let` and the computed
  property is get-only.
- **`/// sourcery: handler` narrows to what distinguishes it:** no storage, and a read with no
  handler set traps with §2.4's string.
- **Isolation is unchanged:** under a global actor a `nonisolated` requirement's storage and
  counters take `nonisolated(unsafe)` and its accessors `nonisolated` (`MockVar.swift:34-45`).
- **A protocol that declares `_<var>` itself collides**, as one declaring `<var>GetCount` does
  today. D9 puts every emitted name under one uniqueness check, so both fail generation naming the
  two members instead of emitting a file that does not compile.

`kotlin-ksp-mocks` emits `SetCount` alone for a stored property (`MockRenderer.kt:127-140`) and its
skill states that absence, so this is the one point where the two dialects differ until that
processor follows. §8 question 4 carries it.

### 2.6 An effectful property requirement generates the accessor it declares

`var x: T { get async throws }` is parsed — `Variable.isAsync` and `Variable.throws` are
`SourceryRuntime`'s `Variable.swift:30` and `:33` — and ignored by the mock template, which emits a
plain stored property that does not satisfy the requirement. `CONTRIBUTING.md` §"Open items" records
the reason it was left: the shape it needs is a computed accessor over a separate backing store, and
that was a naming decision nobody had taken. §2.5 makes that shape every property's, so this case is
the same emission with the effects carried through:

```swift
var config: Config {
    get async throws {
        configGetCount += 1
        if let handler = configGetHandler { return try await handler() }
        return _config
    }
}
var configGetCount: Int = 0
var configGetHandler: (() async throws -> Config)? = nil
var _config: Config
```

- The accessor declares exactly the effects the requirement declares — `get async`, `get throws`,
  `get async throws` — and `<var>GetHandler`'s type carries the same pair.
- Swift has no effectful setter, so an effectful requirement is get-only and generates no
  `SetCount`. `_<var>` stays assignable, which is how a test seeds it.
- A type with no default value is constructor-seeded, as §2.5 leaves it.
- **A typed throw is out of scope.** `get throws(E)` reaches the template as
  `Variable.throwsTypeName` (`Variable.swift:36`), and `Method.throwsTypeName` (`Method.swift:75`)
  is the same fact on the method side; `MockMethod.swift:319-321` writes bare `throws` for a method
  today, and a witness that throws `any Error` does not satisfy a requirement that throws `E`. Both
  paths get one diagnostic naming the member instead of an emission that fails at the consumer's
  conformance (§8 question 1).

### 2.7 A publisher member hands back a construct the mock owns

An `AnyPublisher` member erases its subject at read time and consults its handler there
(`SourceryRuntimeExtensions.swift:360-408`), so the mock records that the code under test asked for
the stream and nothing about what it did with it. The member instead returns a `Deferred` whose
closure the mock owns — the Combine construct closest to the `AnyObserver` the RxSwift branch builds
inline (§2.3, D11):

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
    .handleEvents(
        receiveOutput: { [weak self] value in
            self?.ownMemoriesOutputCount += 1
            self?.ownMemoriesOutputs.append(value)
            self?.ownMemoriesOutputHandler?(value)
        },
        receiveCompletion: { [weak self] _ in self?.ownMemoriesCompletionCount += 1 },
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

A method keeps its handler at call time, where the arguments are and where the member's `async` and
`throws` apply; only the subject fallback is deferred:

```swift
func share(id: String) throws -> AnyPublisher<String, Error> {
    shareCallCount += 1
    shareArgs.append(id)
    if let __shareHandler = self.shareHandler {
        return try __shareHandler(id)
    }
    return Deferred { [weak self, subject = shareSubject] () -> AnyPublisher<String, Error> in
        self?.shareSubscribeCount += 1
        return subject.eraseToAnyPublisher()
    }
    .handleEvents(   // the same three hooks, against the method's own names
        receiveOutput: { [weak self] value in
            self?.shareOutputCount += 1
            self?.shareOutputs.append(value)
            self?.shareOutputHandler?(value)
        },
        receiveCompletion: { [weak self] _ in self?.shareCompletionCount += 1 },
        receiveCancel: { [weak self] in self?.shareSubscribeCancelCount += 1 })
    .eraseToAnyPublisher()
}
```

Five rules the shape carries:

- **The counters record what crossed the member, which is the `AnyObserver` construct's rule read in
  the other direction.** There, `<name>EventCallCount` counts what the code under test pushed in;
  here, `<name>OutputCount` counts what the member delivered out and `<name>CompletionCount` the
  completions. It records delivery rather than sending: a value sent while nobody is subscribed is
  dropped by the `PassthroughSubject` and counts nothing, a value delivered to two subscribers
  counts twice — the same per-recipient multiplicity the observer side has — and a stream supplied
  by `<var>GetHandler` is counted as well, because the operators wrap whatever the closure returned.
  The suffix is Combine's own word for its values, the way D4 takes `cancel()` and `dispose()` from
  their frameworks; `EventCallCount` stays RxSwift's.
- **`<name>SubscribeCount` counts subscriptions and `<name>SubscribeCancelCount` counts the
  cancellations of them.** `<var>GetCount` and `<method>CallCount` keep counting reads and calls, so
  a test can tell "asked for the stream" from "subscribed" from "was actually sent something".
- **`<name>Outputs` records each delivered value and `<name>OutputHandler` runs after it**, in the
  order `<method>CallCount` / `<method>Args` / `<method>Handler` already establishes. A test asserts
  `mock.<name>Outputs == [expected]` with no handler written at all; the handler stays for what a
  recorder cannot do, which is to see each value as it lands and send the next one from inside it —
  how a test drives a chain deterministically without subscribing itself. The other three counters
  have no handler and no recorder (D12): the `AnyObserver` shape this mirrors carries one of each
  for the payload and none for the lifecycle. `<name>SubscribeCount` sits in the `Deferred` closure
  rather than on `handleEvents(receiveRequest:)`, which counts demand requests — measured at 3 for
  two values under `flatMap(maxPublishers: .max(1))`.
- **A property's `<var>GetHandler` is read inside the closure**, so a handler seeded after the code
  under test captured the publisher decides the stream. A method's `<method>Handler` cannot move
  there: it takes the call's arguments and may be `async` or `throws`.
- **The closure captures the subject directly and the mock weakly.** The stream therefore still
  delivers after the mock is released, and only the counting stops. Capturing the mock strongly
  would make every publisher member retain it, which is the hazard `skipArgumentRecording` exists
  for.
- **The subject kind is unchanged.** `subject = "CurrentValue"` still replays to a late subscriber,
  and the default `PassthroughSubject` still delivers nothing to one.

Measured against the shapes above, with Swift 6.3.3: both typecheck at zero diagnostics under
`-swift-version 5 -strict-concurrency=complete` and under `-swift-version 6` on a `@MainActor`
class, and 22 runtime checks pass — reads counted at read and subscriptions at subscribe,
cancellation counted, a handler seeded after capture winning, two subscriptions counted twice, a
`CurrentValue` member replaying to a late subscriber, the default `PassthroughSubject` still
delivering nothing to one and everything after it, the stream still delivering after the mock is
released, a send with nobody subscribed counting no output, one send to two subscribers counting
two, a handler-supplied stream's values and completion counted, and `<name>OutputHandler` firing
after its counter and sending the next value from inside itself. Those checks are what P7 adds to
`Tests/Checks/Behaviour/Main.swift`'s `checkCombineStreams`.

The RxSwift branches keep their shape here. `Observable` and `Single` have
`do(onSubscribe:onDispose:)` as the same hook; §8 question 5 carries whether to mirror it.

### 2.8 What does not change

`<Protocol>Mock`, `Any<Protocol>`, `<X>Component` / `<X>ComponentBase`; name-sorted member emission;
the initializer-seeded bag; argument recording and its opt-outs; what an unset handler returns for
every return type in §1's table; which subject backs a publisher member and what
`subject = "CurrentValue"` does to it; the `methodName`, `handler`, `init`, `const` and `subject`
annotations, with the two meanings §2.5 restates. The member **sets** change in three places only,
each of them additive: §2.5 for every property, §2.6 for an effectful one, §2.7 for a publisher.

---

## 3. Decisions

### D1 — the prefix transform

- **(a) Declared name verbatim (recommended).** One sentence for a reader; removes the trap in §1.2;
  matches `MockRenderer.kt`.
- (b) Apply the method transform to properties too. Makes both sides regular and keeps the method
  names already in consumers' tests, at the cost of renaming every property member whose declaration
  carries an underscore and keeping a transform that no reader can invert.
- (c) Leave it. The measured failure in §1.5 stays, and the rule cannot be stated in `SKILL.md` in
  fewer than a paragraph.

### D2 — the overload long form

- **(a) Selector labels only (recommended).** `end(atDocument:)` → `endAtDocument`. Derivable from
  the selector a reader already writes.
- (b) Keep label plus parameter name. Nothing to migrate for overload-heavy consumers; keeps
  `referenceWithPathPath`, and keeps a rule that takes two sentences and an exception to state.
- (c) Parameter names only, as Kotlin does. Cannot distinguish `update(id:)` from
  `update(with id:)`, which Swift allows and Kotlin cannot express.

Under (a) the residual ambiguity — two overloads with the same labels and different parameter types
— falls to §2.2 step 3 and then to step 4's error. Under (b) the same two overloads are
distinguished whenever their parameter names differ.

### D3 — the "fewest parameters keeps the plain name" tie-break

- **(a) Keep it, and state that the requirement set includes inherited requirements (recommended).**
  It is what `MockRenderer.kt:83-97` does, and it is what keeps a test compiling when a wider
  overload is added later.
- (b) Give every member of an overload group the long form. Removes the tie-break but not the
  set-dependence — whether a group exists at all still depends on the refinement closure — and
  renames every short-form overload in every consumer.

§1.4's `data()` case is reached by either option: it is the return-type fallback, and the only
control a declaration has over it is `methodName = "…"`. P8 documents that.

### D4 — the returned-token suffix

- **(a) Keep `Dispose*` for `Disposable` and `Cancel*` for `AnyCancellable`, and correct
  `SKILL.md:202` (recommended).** Each suffix is the call the returned token exposes —
  `Disposable.dispose()`, `AnyCancellable.cancel()` — so a reader who knows the framework derives
  the member, and no RxSwift consumer is renamed.
- (b) Rename `Dispose*` to `Cancel*`. One suffix across both frameworks and one row fewer in §2.3's
  table, against a rename no measurement asked for and a member named after neither the declaration
  nor the framework's own verb.

Under (a) the correction is a documentation one: `SKILL.md:202` documents `<method>CancelCallCount`
for `Disposable` and `AnyCancellable` alike, and states each against its own return type instead
(P8).

### D5 — where the rule is implemented

- **(a) One file, `templates/Mocks/MockNaming.swift` (recommended).** It holds the prefix derivation
  for a method and for a property, the overload chain, every suffix, and the two `fatalError`
  strings. `MockMethod.swift`, `MockVar.swift` and `SourceryRuntimeExtensions.swift` call it; the 32
  interpolation sites in §1.8 become calls.
- (b) Leave the sites where they are and document the rule. A member added at its own site picks its
  own words there, which is how the method trap string (`MockMethod.swift:146`) and the property one
  (`MockVar.swift:91`) came to differ by three words and a pair of backticks (§1.8).

### D6 — migration aids for consumers

- **(a) None beyond the CHANGELOG (recommended).** Every stale name is a compile error naming the
  member and the type. `CHANGELOG.md` carries the rule change, the three categories of rename and
  the worked list from §5.
- (b) Emit `@available(*, deprecated, renamed:)` aliases for one release. The generator would have
  to keep both rules to know the old name, which is the condition this spec removes.

### D7 — the drift gate

- **(a) Review-only, for now (recommended; decided when this spec was commissioned).** The snapshot
  diff under `Tests/Checks/Snapshots/` is where a naming change becomes visible; `AGENTS.md` gains
  one line naming `MockNaming.swift` as the single home, under §"State a rule once".
- (b) A check in `run-checks.sh` failing on a suffix literal outside `MockNaming.swift`: one
  `grep -nE` over `templates/Mocks/`, plus its red control under `--self-test`. Deferred until the
  rule stops moving; §8 question 3 states the trigger.

### D8 — a read counter on every property

- **(a) `GetCount`, `GetHandler` and the `_<var>` store on every property requirement
  (recommended).** One sentence then covers every property, and a run stops having to read the
  generated file to learn which members a property has. The Kotlin arm at round 3 planned 20 cases
  against a `value6_0GetCount` that does not exist (`findings/what-the-runs-said-about-the-work.md`
  §2).
- (b) `GetCount` alone on a stored property. Same mechanics — a read cannot be counted without a
  backing store — for a vocabulary that still needs `GetHandler`'s exception stated.
- (c) Leave stored properties uncounted and state the exception in `SKILL.md`'s body, which is the
  one-line move the Kotlin run asked for in its own repository.

(a) and (b) cost the same rewrite and the same regenerate diff: 21 property members in
`Tests/Checks/Snapshots/Mocks.generated.swift` and 73 in `modaal-firebase-wrappers` change shape
(§5). (c) costs one sentence and keeps `kotlin-ksp-mocks` comparable on this point.

### D9 — the backing store's name, and collisions in general

Nothing checks a property's generated names today. `MockMethod.from` guards duplicate *method* names
(`MockMethod.swift:24-26`); `MockVar.from` uniques the requirements by name and nothing more
(`MockVar.swift:17-20`), so a protocol declaring both `draft` and `draftGetCount` emits two
`var draftGetCount` declarations and the generated file does not compile, with no diagnostic from
the template saying why. §2.5 adds one more name per property to that surface.

- **(a) Spell the store `_<var>`, and put every emitted name under one uniqueness check
  (recommended).** The check lives beside the rest of the vocabulary in `MockNaming.swift`, covers
  methods, properties and bookkeeping alike, and fails generation naming the protocol, the two
  members and `methodName = "…"`. It subsumes §2.2 step 4 and closes the property gap that predates
  this spec. The underscore is what the generator already uses for names it owns — `__<name>Handler`
  for the handler local inside every generated method (`MockMethod.swift:243-244`).
- (b) Spell it `<var>Storage` with the same check. Self-describing at the use site
  (`mock.draftStorage`), and a likelier collision: a protocol declaring `draftStorage` is more
  plausible than one declaring `_draft`.
- (c) No store, because no stored property is counted — D8 option (c), where the question does not
  arise and the `<var>GetCount` collision stays unchecked.

The check is what decides the outcome under (a) and (b) alike: a spelling only changes the odds, and
this generator already has one collision class that reaches the consumer's compiler rather than a
diagnostic.

### D10 — effectful property requirements

- **(a) Implement them with §2.5's shape (recommended).** The work is the accessor's effects and the
  handler's type; `CONTRIBUTING.md` §"Open items" gives the blocker as the missing naming decision,
  which §2.5 takes. It costs one phase (P6) and one fixture, and it closes an open item rather than
  adding one.
- (b) Leave them, and keep the open item. The template keeps emitting a property that does not
  satisfy the requirement, which fails at the consumer's conformance rather than in generation — the
  outcome `CONTRIBUTING.md` §"Design rules already decided" rules out for a Component.
- (c) Reject them with a diagnostic. Cheaper than (a) by one phase, and it removes a shape the
  Component template already forwards (`Tests/Checks/Fixtures/Forwarding.swift`,
  `ProfileDependency`).

Typed throws stays out under all three (§2.6, §8 question 1).

### D11 — what an `AnyPublisher` member returns

`AnyObserver` is a sink: the mock builds it inline and the closure it owns counts every event the
code under test pushes (`SourceryRuntimeExtensions.swift:345-354`). `AnyPublisher` is a source, and
Combine has no closure-based initializer to mirror that shape — `AnyPublisher.init` takes a
publisher, where RxSwift's `AnyObserver.init` takes an event handler. The two constructs that give a
mock a closure of its own on the source side are `Deferred`, whose closure runs once per
subscription and returns the publisher to use, and
`handleEvents(receiveSubscription:receiveCancel:)`, which observes without changing the stream.

Both compile at this repository's gate — measured on a `@MainActor` class with Swift 6.3.3, zero
diagnostics under `-swift-version 5 -strict-concurrency=complete` and under `-swift-version 6` — and
the tree already mutates a counter from an escaping closure on an isolated mock
(`Tests/Checks/Snapshots/Mocks.generated.swift:52-56`).

- (a) Keep the subject and count subscriptions, without the closure. The getter erases
  `<name>Subject.handleEvents(…)` instead of the bare subject and gains `<name>SubscribeCount` and
  `<name>SubscribeCancelCount`. No stream semantics change, no consumer break, and a test can assert
  that the code under test actually subscribed rather than inferring it from `<name>GetCount`.
- **(b) Emit the `Deferred` construct, keeping the subject as its fallback (recommended, and §2.7
  states it).** The member returns a closure the mock owns, which counts the subscription, consults
  `<name>GetHandler` / `<name>Handler` and falls back to `<name>Subject`. It subsumes (a)'s counting
  and it makes a handler set *after* the code under test captured the publisher take effect, because
  the handler is read at subscribe time rather than at read time. The consequence I expected it to
  carry — a publisher held past the mock's life going `Empty` — does not arise: the closure captures
  the **subject** directly and the mock weakly, so the stream still delivers and only the counting
  stops (§2.7, measured). Capturing the mock strongly instead would make the returned publisher
  retain it, which is the hazard `skipArgumentRecording` exists for.
- (c) Make `.automatic` mean "no subject": the member returns what `<name>GetHandler` /
  `<name>Handler` gives and traps when unset, and `subject = "Passthrough"` becomes the opt-in.
  **Not recommended.** 11 of the 13 subject-backed members in
  `Tests/Checks/Snapshots/Mocks.generated.swift` are un-annotated and would trap on first read until
  seeded; `CONTRIBUTING.md` §"Design rules already decided" records the subject default as taken;
  and `kotlin-ksp-mocks` channel-backs every `Flow` member for the same reason
  (`MockRenderer.kt:116`, `:183`), so the dialect would differ on the shape both generators are most
  used for.

- (d) Generate a publisher type of our own — an `EmittingPublisher<Output, Failure>` built from a
  closure, which is the literal translation of `AnyObserver.init(eventHandler:)`. It can be emitted
  without colliding: `Mocks.swifttemplate` would declare it `private`, which is file-scoped in
  Swift, the way `TypeErase.swifttemplate:46` already emits `private class _Any<Type>Base` — and
  that matters, because a module can hold several generated files, seven of them in
  `modaal-firebase-wrappers/Sources/ModaalFirebaseMocks/Generated/`. What it costs is a
  `Subscription` that honours `request(_:)`: a custom publisher that ignores demand misbehaves under
  `flatMap(maxPublishers:)`, `buffer` and `zip`, `PassthroughSubject` already implements that
  correctly, and the demand behaviour of generated code would become something
  `Tests/Checks/Behaviour/Main.swift` has to cover. (b) gives the same closure ownership with no
  type and no demand code.

§2.3 gains `SubscribeCount`, `SubscribeCancelCount`, `OutputCount` and `CompletionCount` against a
publisher member, §2.5 is unaffected, and the work is P7. The output pair is what makes the
publisher member the mirror of the `AnyObserver` one rather than only a subject with a subscription
count; naming it `<name>EventCallCount` instead would give a cross-platform codebase one word for
"crossed this member" at the cost of D4's rule that a suffix is the framework's own word, and it is
a one-word change if that trade is worth making. `modaal-firebase-wrappers` has no publisher
requirement in any mocked protocol, so its regenerate diff does not move under any of the four; the
13 subject-backed members in `Tests/Checks/Snapshots/Mocks.generated.swift` each gain two counters
and five lines.

**What the Kotlin twin would do.** Nothing it needs a new type for: a replayed flow takes
`onStart`/`onCompletion`, so `<prop>Channel.receiveAsFlow().onStart { … }` carries the same two
counters D11 (a) adds here. Three facts about that side, for whoever takes the separate iteration
(§8): `flowElement` matches `kotlinx.coroutines.flow.Flow` exactly (`KspMocksProcessor.kt:147`), so
a `StateFlow` or `SharedFlow` requirement is not channel-backed but constructor-seeded — usable, and
undocumented in that skill's property table; a sink-shaped requirement (`FlowCollector`,
`SendChannel`) reaches no branch there, which is the same gap Combine's `AnySubscriber` has here (§8
question 4); and `EventCallCount` has no Kotlin counterpart at all, which neither repository's twin
table says — `skills/swift-sourcery-mocks/references/generated-api.md:218` names only
`<method>CancelCallCount`, and
`kotlin-ksp-mocks/skills/kotlin-ksp-mocks/references/generated-api.md:212` names the same one.

### D12 — which counters get a handler

`<method>CallCount` has `<method>Handler`, `<var>GetCount` has `<var>GetHandler`,
`<method>EventCallCount` has `<method>EventHandler`, and the two token counters have theirs.
`<var>SetCount` does not, and §2.7 adds four more counters.

- **(b) Add `<name>OutputHandler` alone (taken).** It is the mirror of `<method>EventHandler` — the
  payload crossing the member, pushed in on an `AnyObserver`, delivered out on an `AnyPublisher`.
  `<name>SubscribeCount`, `<name>SubscribeCancelCount` and `<name>CompletionCount` stay counters,
  because the shape being mirrored carries no handler for the lifecycle, and `<var>SetCount` stays
  as it is.
- (a) Pair every counter with a handler: `<var>SetHandler`, `<name>SubscribeHandler`,
  `<name>SubscribeCancelHandler` and `<name>CompletionHandler` as well. Measured to work — each
  fires after its counter and the shape compiles at the gate — and rejected as speculative: no
  measurement asked for them, and an `AnyPublisher` requirement would carry 12 members against 9.
- (c) No new handlers, leaving the `AnyObserver` and `AnyPublisher` shapes asymmetric on the one
  member a test reaches for.

**The rule this sets for what comes next:** a counter gets a handler where the construct being
mirrored has one. That is D4's rule applied to handlers instead of suffixes — take the shape from
what is being mirrored rather than from what would be symmetrical on paper.

One measured fact (b) removes the need to document: a `send` made synchronously from inside a
subscribe-time hook is dropped, because Combine has not established demand at that point — true of
the `Deferred` closure, of `handleEvents(receiveSubscription:)` and of `(receiveRequest:)`, while
the same send scheduled with `DispatchQueue.main.async` is delivered. With (b) there is no such hook
for a test to write it in: it seeds `<name>Subject` after the code under test has subscribed, or
supplies a stream through `<var>GetHandler`, which is what `README.md` §"Combine" already says.

### D13 — recording what a stream member carried

A method records its arguments; a stream member records nothing. §1.9 measures what that costs: in
43 spec files of a consumer, `<name>EventHandler` is assigned **0** times and the one assertion on
an `AnyObserver` member checks a count while the code under test pushes a particular value. In a
consumer whose mocks do record, `Args` outnumbers `CallCount` 15 to 2.

- **(a) Record on both stream shapes (recommended).** `<name>Events: [Event<Element>]` on an
  `AnyObserver` member, `<name>Outputs: [Output]` on an `AnyPublisher` one, appended before the
  handler runs. `skipArgumentRecording` already means "do not retain what crossed this member" and
  covers both, which needs its registry record's target widened from protocol and method to
  protocol, method and variable (`templates/Annotations/AnnotationRegistry.swift`, and the tables
  `Scripts/render-annotations.sh` renders).
- (b) Record on the publisher only. Leaves the observer member — the one §1.9 measures a test giving
  up on — as it is.
- (c) No recorder. A test that wants the value writes a handler that appends into its own array,
  which no spec file in that consumer does for any member.

Two facts (a) has to carry. A publisher records per subscription, so one send to two subscribers
appends twice, matching `<name>OutputCount`. And RxSwift's `Event` has no `Equatable` conformance
(`Event.swift:13-101`), so `<name>Events` is read through `compactMap(\.element)`, `error` and
`isCompleted` rather than compared whole; `[Output]` compares directly.

---

## 4. Phasing

**P1 — extract, with no change to output.** Add `templates/Mocks/MockNaming.swift` and route the 32
sites of §1.8 through it, moving today's rules verbatim, including the transform. Gate:
`Tests/Checks/run-checks.sh` passes with no `--record` — the snapshots are byte-identical. This
phase is the one that makes P2–P4 reviewable as one diff each.

**P2 — the prefix (§2.1, D1).** Delete `swiftifiedMethodName` and whatever in
`templates/Utility/StringLettercase.swift` is left with no caller (`camelCased` is also used by
`returnTypeDiscriminatorSuffix`, `uppercasedFirstLetter` by the overload long form). New fixtures in
`Tests/Checks/Fixtures/Vocabulary.swift` or a file beside it: a method whose name carries an
underscore next to a property whose name does, an all-uppercase method name, a backtick-escaped
method name, and a protocol whose two methods collide under the old transform and do not under the
new one. Run the gates, read the snapshot diff, then `--record`. The prefix is what the RxSwift and
type-erasure branches interpolate, so `Tests/Examples/ExampleProjectSpm/test-ios.sh` runs too
(`AGENTS.md` §"Review generated output as a snapshot diff").

**P3 — the overload long form and the collision check (§2.2, D2, D9).** The check over every emitted
name lands here, covering properties and bookkeeping as well as overloads, so P5's `_<var>` arrives
under a guard that already exists. Fixtures: an overload pair whose argument label differs from the
parameter name, one that reaches §2.2 step 4, and a red control — a protocol declaring both `draft`
and `draftGetCount` — which `run-checks.sh` runs the way it runs the near-miss section, since a
fixture that fails generation fails the whole lane. Snapshot diff, then `--record`.

**P4 — the diagnostic wording (§2.4).** One emitted string changes (`MockVar.swift:91`), and
`Tests/Checks/Fixtures/` has to carry a `handler`-annotated property for the snapshot to show it. No
suffix moves: D4 keeps `Dispose*` and `Cancel*` against their own return types, and what is left is
the documentation correction in P8.

**P5 — the property read counter (§2.5, D8, D9).** `MockVar.swift`'s stored branch becomes a
computed accessor over `_<var>`, and `MockGenerator.swift:69-77` assigns the store while keeping the
initializer's argument label. Gates: the snapshot diff (21 property members change shape), both
language modes, and `Tests/Checks/Behaviour/Main.swift` gaining two checks — construction counts no
set, one read counts one get. This phase is separable from P2–P4 and can be taken alone.

**P6 — effectful property requirements (§2.6, D10).** `MockVar.swift` reads `variable.isAsync` and
`variable.throws` and writes them into the accessor and the handler type; a typed throw is refused
with a diagnostic naming the member. Fixture: `Tests/Checks/Fixtures/` gains a `ProtocolMock`
protocol carrying `{ get async throws }`, `{ get async }` and `{ get throws }` — today the only
effectful requirement in the tree is `Forwarding.swift:105`, which is `DuetComponent` alone, so the
mock template has never seen one. `Tests/Checks/Behaviour/Main.swift` awaits one and catches one.
Depends on P5.

**P7 — the publisher construct and the stream recorders (§2.7, D11, D13).** The `AnyObserver` branch
(`SourceryRuntimeExtensions.swift:345-354`) gains `<name>Events`, and
`templates/Annotations/AnnotationRegistry.swift`'s `skipArgumentRecording` record widens to
variables. `SourceryRuntimeExtensions.swift`'s `AnyPublisher` branch (`:360-408`) emits the
`Deferred`, and `MockVar.swift` stops consulting `<var>GetHandler` at read time for a publisher
property — the one place where the property branch and the smart-default branch have to agree, so
both go through `MockNaming.swift`'s member names and one emission. Gates: the snapshot diff (13
publisher members, four counters, one handler and one recorder each), both language modes,
`checkCombineStreams` gaining the checks §2.7 measured, and a behaviour check that
`skipArgumentRecording` suppresses both recorders. The `AnyObserver` half needs
`Tests/Examples/ExampleProjectSpm/test-ios.sh`, which is where that shape is covered. Independent of
P2–P6.

**P8 — the documents.**

- `skills/swift-sourcery-mocks/SKILL.md`: a block in the body stating §2.1 in one sentence, §2.2 in
  three lines, the §2.3 table (replacing the current one, `:202`'s correction included), and one
  line each for §2.5's property members, §2.6's effectful accessor and §2.7's subscription counters.
  The body is 250 lines against the 400-line ceiling (`AGENTS.md` §"The skill is for adopters").
- `skills/swift-sourcery-mocks/references/generated-api.md`: the worked examples, the full overload
  chain including step 4, §1.4's refinement case with `methodName` as the answer, §2.5's property
  shape, §2.7's publisher shape with the late-seeded handler spelled out, and the twin table gaining
  the rows where the two generators now differ — `Dispose*` beside `Cancel*`, the stored-property
  read count, and the subscription counters.
- `skills/swift-sourcery-mocks/references/troubleshooting.md`: a row for `has no member '<name>'`
  naming §2.1 and §2.2, a row for a property read count that moved because the test read the
  property rather than `_<var>` (§2.5), and a row for `<name>SubscribeCount` staying at zero because
  the code under test read the publisher without subscribing (§2.7).
- `README.md` §"Generated Mock API": the same rule statement and the §2.3 table. §"Combine": the
  subject is still what a test drives, `<name>SubscribeCount` is how it asserts the code under test
  subscribed, and a `<var>GetHandler` set after the publisher was captured now takes effect.
- `CONTRIBUTING.md` §"Where to change what": a subsection naming `MockNaming.swift` as the place a
  member name is built; §"Design rules already decided": the rule in §2.1–§2.7, with the publisher
  entry amended rather than replaced — the subject and its default are unchanged, and what is added
  is the construct around them; §"Open items": the effectful-property entry deleted, since P6 closes
  it, and typed throws added in its place (§8 question 1).
- `AGENTS.md` §"State a rule once" and its `CLAUDE.md` copy: one line naming `MockNaming.swift`.
- `kotlin-ksp-mocks/skills/kotlin-ksp-mocks/references/generated-api.md`: the sentence recording
  that the Swift property getter traps with different words is superseded by §2.4, and the twin
  table gains two rows the two generators do not share — the stored-property read count, and
  `<method>EventCallCount` for an `AnyObserver` member, which neither table names today (D11). A
  follow-up in that repository, and adopting §2.5 there is a separate iteration (§8).
- `skills/swift-sourcery-mocks/references/generated-api.md`'s twin table, the same two rows from
  this side.
- `Tests/Evals/`: a sixth case asking what a test asserts on for a protocol whose members carry
  underscores and one overload pair. `.claude-plugin/plugin.json`'s `experimental.evals` already
  names the directory; SC13 checks the case parses.

**P9 — release.** `CHANGELOG.md` entry under the format that file's header states: **Generated
output** (the two rename categories of §2.1 and §2.2 with before/after, and §2.5's added property
members), **Breaking** (every test naming a renamed member stops compiling; regenerate and fix what
the compiler names), **Adopting** (the two lanes' regenerate commands, and `_<var>` for a test that
reads a mock property without moving its count). The entry is written before the tag, and the
consumer delta in §5 is measured into it (`AGENTS.md` §"Do not tag without measuring the consumer").

---

## 5. What rides along from 003

003 §4 option 1 — bump `modaal-firebase-wrappers` and commit its regenerated output — stops being
optional under this change: that repository is pinned at templates `0.2.15`
(`scripts/generate-mocks.sh:9`), and a consumer five releases behind cannot show a one-release delta
for the entry P9 writes. 003 §4 option 2 (state the two-generation method in `CONTRIBUTING.md`)
remains independent and is not required here.

**What the bump costs, measured.** Regenerating that repository against `master` produced
`7 files changed, 218 insertions(+)`, no deletions (003 §1.4). This change adds renames and property
members on top. Its 47 long-form method member groups were re-derived with a script implementing
§2.2 step 2; the script reproduces 37 of the 47 names the templates actually emitted, the 10 misses
being the four return-type-discriminated `data…` names it does not implement and six whose trailing
closure parameter its splitter drops:

- **§2.1 renames: none.** No protocol in that repository declares a method whose name carries an
  underscore or leading capitals.
- **§2.2 renames: 27 member groups, 15 distinct names** — `referenceForURLUrl` → `referenceForURL`,
  `referenceWithPathPath` → `referenceWithPath`, `signInWithEmailEmailPasswordCompletion` →
  `signInWithEmailPasswordCompletion`, `endAtDocumentDocument` → `endAtDocument`, `endAtFieldValues`
  → `endAt`, `endBeforeDocumentDocument` → `endBeforeDocument`, `endBeforeFieldValues` →
  `endBefore`, `limitToValue` → `limitTo`, `limitToLastValue` → `limitToLast`,
  `startAtDocumentDocument` → `startAtDocument`, `startAtFieldValues` → `startAt`,
  `startAfterDocumentDocument` → `startAfterDocument`, `startAfterFieldValues` → `startAfter`,
  `setDataDataForDocumentDocumentMerge` → `setDataDataForDocumentMerge`,
  `setDataDataForDocumentDocumentMergeFields` → `setDataDataForDocumentMergeFields`. Each carries a
  `CallCount`, a `Handler` and, where the method records, an `Args`.
- **§2.3 renames: none.** D4 keeps `Dispose*` and `Cancel*` apart, and that repository declares no
  `Disposable` or `AnyObserver` return type in any case.
- **§2.4 changes: none.** No declaration in that repository carries `/// sourcery: handler`, so no
  property getter traps there.
- **§2.5 additions: 73 property members** gain `GetCount`, `GetHandler` and the `_<var>` store, at
  four added lines each. Additive: nothing that compiles against those mocks today stops compiling,
  and the count is comparable to the 218 insertions the version bump alone produces.
- **§2.6 changes: none.** No requirement in that repository is declared `{ get async }`,
  `{ get throws }` or `{ get async throws }`.
- **§2.7 and D12 additions: none** — no mocked protocol there declares an `AnyPublisher` member.

Its own tests carry 127 references to a mock member; **9 of them, in 2 files, name a member §2.2
renames** — `setDataDataForDocumentDocumentMerge` (4), `setDataDataForDocumentDocumentMergeFields`
(4) and `signInWithEmailEmailPasswordCompletion` (1). The rest of the renames land only in the
committed generated files, and in whatever repository downstream imports that mocks module.

---

## 6. What a consumer does

1. **Plugin lane** — rebuild. The mock regenerates and the compiler names every test that used a
   renamed member.
2. **CLI lane** — `mock-templates generate`, then `mock-templates validate` in CI. The fingerprint
   block changes with the body.
3. **What to expect**, in the order a codebase is likely to hit it: an overloaded method whose
   argument label differs from its parameter name (§2.2); a method whose declared name carries an
   underscore or leading capitals (§2.1). A method returning an RxSwift `Disposable` keeps
   `<method>DisposeCallCount` (D4).
4. **A property read starts counting.** `mock.draft` moves `draftGetCount`; `mock._draft` reads and
   seeds the same value without moving a counter (§2.5).
5. **A publisher member gains four counters** — `<name>SubscribeCount`,
   `<name>SubscribeCancelCount`, `<name>OutputCount`, `<name>CompletionCount` — and one handler,
   `<name>OutputHandler`, and one recorder, `<name>Outputs` — an `AnyObserver` member gains
   `<name>Events` the same way; a property's `<var>GetHandler` is read when the code under test
   subscribes rather than when it reads the property (§2.7). Driving `<name>Subject` is unchanged,
   and a value sent while nobody is subscribed still goes nowhere; `<name>OutputCount` is how a test
   sees that.
6. A member that must keep its old name takes `/// sourcery: methodName = "oldName"` on the
   declaration.

---

## 7. Not measured

- Whether `SourceryRuntime.Variable.name` carries backticks for a keyword-named property (``var
  `default`: Int``). It decides whether §2.1's backtick removal is load-bearing on the property path
  or a no-op. No fixture declares one.
- Whether any consumer declares an all-uppercase method name. Neither `modaal-firebase-wrappers` nor
  `Tests/Examples/` does; the trap in §1.2 is reachable but unobserved in the wild.
- How much of the Swift G ÷ H ratio in §1.5 the rule change recovers. The lab's grouping key carries
  `tool_sha256` and `skill_sha256` (`RESULTS.md` §"In flight"), so rows measured after this change
  cannot be averaged with rows measured before it: the comparison is a re-run of `swift-G` at round
  3 on the same seeds, against the recorded rows.
- Whether `Tests/Evals`' five existing cases change answers under the new `SKILL.md` block. Each
  case is model calls and no CI job runs them.
- How often a consumer's test reads a mock property inside an assertion. §2.5 makes those reads move
  `<var>GetCount`, which can fail no build and can only change what a *new* assertion on that count
  would read.

## 8. Open questions

1. **What does a typed throw generate?** `get throws(E)` and `func f() throws(E)` reach the
   templates as `Variable.throwsTypeName` and `Method.throwsTypeName`, and
   `MockMethod.swift:319-321` writes bare `throws` for the method case today. A witness throwing
   `any Error` does not satisfy a requirement throwing `E`, so both paths need either the typed form
   emitted or a diagnostic; §2.6 chooses the diagnostic and does not measure what emitting the typed
   form would cost. No fixture and no consumer protocol in reach declares one.
2. **Does `public` mock generation interact with this?** `CONTRIBUTING.md` §"Open items" lists the
   member sites an access-level change would touch — `MockGenerator.swift`, `MockMethod.swift`,
   `MockVar.swift` — which are the same sites P1 moves. Doing P1 first makes that change one file
   smaller; doing them together doubles the review.
3. **When does D7(b) stop being deferred?** The trigger is the rule no longer moving: after P5 lands
   and one release has been cut against it.
4. **Does a consumer need `AnySubscriber`?** Combine's dual of `AnyObserver` reaches no branch of
   `smartDefaultValueImplementation` and falls through to `MockError.noDefaultValue`, so a
   requirement returning one is constructor-seeded or traps for want of a handler. It is a coverage
   gap rather than a naming one, and no protocol in reach declares it. What an `AnyPublisher` member
   could count instead is D11.

5. **Do the RxSwift branches mirror §2.7?** `Observable` and `Single` expose
   `do(onSubscribe:onDispose:)`, which is the same hook `Deferred` plus `handleEvents` gives on the
   Combine side, and `AnyObserver` already counts what the code under test delivers. Unmeasured:
   whether `asObservable()` on a `PublishSubject` composes with it at the gate, and whether any
   consumer asserts subscription counts today by other means. The example lane
   (`Tests/Examples/ExampleProjectSpm/test-ios.sh`) is the only place it could be measured.

**Decided, and recorded here because the question was asked:** `kotlin-ksp-mocks` adopting §2.5 is a
separate iteration in that repository. Until it lands, its stored-property branch emits `SetCount`
alone (`MockRenderer.kt:127-140`) and the twin table in each repository names the row the other does
not carry (P8).

---

## 9. What landed

Appended as each phase of §4 completes, one entry per phase: what the phase changed, what gate it
passed, and where it departed from the plan.

### P1 — `MockNaming.swift` extracted, output unchanged

`templates/Mocks/MockNaming.swift` (156 lines) now holds the prefix derivation, the overload
component and group key, the return-type discriminator, every suffix, the handler local's spelling
and the two `fatalError` strings. The rules moved verbatim, the §1.2 transform included, under the
name `swiftifiedMemberName` — §2.1 deletes it in P2.

The 32 sites of §1.8 are calls: `MockMethod.swift` routes `mockedMethodName`,
`returnTypeDiscriminator`, `mockedVarCallCountName`, `mockedVarArgsName`, `mockMethodHandlerName`,
`shortNameKey`, the handler local and the trap string; `MockVar.swift` routes `mockedVariableName`
and its `GetCount` / `GetHandler` / `SetCount` / trap sites; `SourceryRuntimeExtensions.swift` routes
`Subject`, `EventCallCount`, `EventHandler`, `CancelCallCount`, `CancelHandler`, `DisposeCallCount`
and `DisposeHandler`. `Mocks.swifttemplate` and `Component.swifttemplate` both `includeFile` the new
file before `Mocks/MockMethod` — the Component template compiles the same mock sources.

Two names the module does **not** own, and why: the emitted property's own name (`var <var>:` in
`MockVar.mockImpl`) is the protocol requirement's name and is what the conformance is checked
against, not a bookkeeping name; and `<Protocol>Mock` itself, which `MockGenerator.swift:54` builds
and §2.8 leaves unchanged.

Gate: `Tests/Checks/run-checks.sh` passed with no `--record` — both snapshots byte-identical, both
language modes clean, all behaviour checks green. `run-annotation-checks.sh` and
`run-skill-checks.sh` pass.

### P2 — the prefix is the declared name

`MockNaming.swiftifiedMemberName` is gone. `methodPrefix`, `overloadGroupKey` and `variablePrefix`
each strip backticks and do nothing else, so §2.1's table is what the templates emit.

`templates/Utility/StringLettercase.swift` went from 147 lines to 101: `lowercasedFirstWord`,
`lowercasedFirstLetter` and `snakeCased`, and the private `lowerFirstWord`, `lowerFirstLetter` and
`camelToSnakeCase` behind them, had no caller left. `uppercasedFirstLetter` and `camelCased` stay,
both called only from `MockNaming.swift` and only by the overload long form and the return-type
discriminator. The file that crashed generation on `func ID()` (§1.2) is deleted rather than fixed.

**Backtick removal on the property path is load-bearing, which §7 recorded as unmeasured.**
`Tests/Checks/Fixtures/Naming.swift` declares ``var `default`: Int { get set }``;
`SourceryRuntime.Variable.name` carries the backticks, so the witness is emitted as
``var `default`: Int = 0`` and the counter as `defaultSetCount`. Without the strip the counter would
have been `` `default`SetCount ``, which is not an identifier.

`Tests/Checks/Fixtures/Naming.swift` (four protocols, 11 requirements) is the new coverage:
`NamingUnderscores` puts `func perform1_0()` beside `var setting4_2: Int { get set }`, which is §1.1;
`NamingManyToOne` declares `load_data()` and `loadData()`, which failed generation with "not all
duplicates resolved" before this phase and now carry `load_dataCallCount` and `loadDataCallCount`;
`NamingUppercase` declares `ID()` and `URLSession()`, the §1.2 trap; `NamingKeywords` declares
``var `default```, ``func `do`()`` and ``func `repeat`(times:)``.

**No existing fixture member was renamed.** The recorded diff is 110 added lines and no deleted
line: every declaration under `Tests/Checks/Fixtures/` was already lowerCamelCase with no
underscore, which the old transform mapped to itself. That matches §5's finding for
`modaal-firebase-wrappers` — §2.1 renames there: none — and means the transform's failures were
reachable only through declarations no fixture carried.

Gates: `Tests/Checks/run-checks.sh`, diff read, then `--record`; both language modes clean; all
behaviour checks pass. `Tests/Examples/ExampleProjectSpm/test-ios.sh`: 19 tests, 0 failures — the
RxSwift, type-erasure and return-type-overload specs assert on prefixes this phase could have moved
and did not. That script resolves its scheme from the working directory, so it runs from
`Tests/Examples/ExampleProjectSpm/`, not from the repository root; P8 adds that to `CONTRIBUTING.md`.

### P3 — the overload long form, and one collision check over every emitted name

`MockNaming.overloadComponent` returns `(argumentLabel ?? parameterName).withoutBackticks
.uppercasedFirstLetter()`, which is §2.2 step 2. `Tests/Checks/Fixtures/Naming.swift` gains
`NamingOverloads`, whose five requirements produce `end`, `endAt`, `endAtDocument`,
`referenceForURL` and `referenceWithPath` — §2.2's table, with `end()` keeping the plain prefix as
the fewest-parameters overload (D3).

`MockNaming.checkForCollisions(amongMemberDeclarations:typeName:)` reads the names back out of the
declarations the class emits. `MockGenerator.generate` calls it once per type, after every member
has been emitted, over `mock.nested.map { $0.line }` — which is exactly the class's direct members,
because both `MockVar.mockImpl` and `MockMethod.mockImpl` return the witness and its bookkeeping as
siblings. Reading the emitted declarations rather than enumerating names at each site is what makes
it cover the branches in `SourceryRuntimeExtensions.swift` — `Subject`, `EventCallCount`,
`CancelHandler` and the rest — without those sites being edited, and what makes P5's `_<var>` and
P7's six publisher members arrive already checked.

`declaredPropertyName(inDeclaration:)` reads `var` and `let` only, after stripping
`nonisolated(unsafe) `, `nonisolated ` and `lazy `. Two `func`s may share a base name — they are the
protocol's own overloads and Swift allows them — while two properties of one class may not, and
every bookkeeping member is a property.

`MockError.internalError("not all duplicates resolved")` is replaced at `MockMethod.from` by
`MockError.collidingMemberNames(typeName:memberName:)`, so §2.2 step 4 and D9's property case now
produce one wording: the mock class, the member declared twice, and the two fixes — rename the
requirement, or `/// sourcery: methodName = "customName"` on a method.

`run-checks.sh` gains a **collision** section (now gate 4 of 6), built like the near-miss one
because each case has to fail generation and a fixture that fails takes the whole lane's generation
with it. Two cases, each asserted to fail *and* to name its protocol and its member:

| case | declarations | message names |
| --- | --- | --- |
| `bookkeeping` | `var draft { get set }` beside `var draftSetCount { get set }` | `CollidingBookkeeping`, `draftSetCount` |
| `overload` | `send(to target: String)` beside `send(to target: Int)` | `CollidingOverload`, `sendToVoidCallCount` |

The second is §2.2 step 4 reached: the long form gives both `sendTo`, the return-type discriminator
appends `Void` to both, and the name that collides is therefore `sendToVoidCallCount` — the
discriminator is in the message because it is in the name the mock would have declared.

Gates: `run-checks.sh`, diff read, then `--record`; no existing fixture member was renamed (110
added lines, no deleted line — no fixture declared an overload whose argument label differs from its
parameter name); both language modes clean; behaviour checks pass;
`Tests/Examples/ExampleProjectSpm/test-ios.sh` 19 tests, 0 failures, which is where the
return-type-discriminated `data()` overloads are exercised.

### P4 — one wording for both traps

`MockNaming.getHandlerExpectedMessage(prefix:)` now returns
`handlerExpectedMessage(handlerName: getHandler(prefix))`, so the property form is the method form
with the property's handler name in it: `snapshotGetHandler expected to be set.` replaces
`` `snapshotGetHandler` must be set! ``. One function produces both, which is what stops them
drifting again.

`Tests/Checks/Fixtures/Properties.swift` is new and declares `PropertyShaped`, one requirement per
branch of `MockVar.mockImpl`: `identifier` (read-only, synthesizable default), `draft`
(`{ get set }`), `themeProvider` (no default, initializer-seeded), `buildNumber`
(`/// sourcery: const`, emitted `let buildNumber: Int = 0`), `snapshot` (`/// sourcery: handler`,
read-only) and `cursor` (`/// sourcery: handler`, `{ get set }`).

**Nothing under `Tests/` carried `/// sourcery: handler` before this file**, so the string that
diverged from the method's appeared in no generated file this repository holds — which is how it
stayed divergent. The two `handler` requirements put both emission shapes in the snapshot: a
read-only one whose getter is the property body, and a mutable one whose `get` traps while its `set`
counts.

No suffix moved in this phase. D4 keeps `Dispose*` against `Disposable` and `Cancel*` against
`AnyCancellable`, and the `SKILL.md:202` correction that documents each against its own return type
is a document change, in P8.

Gates: `run-checks.sh`, diff read, then `--record` — 39 added lines, no deleted line; both language
modes clean; behaviour checks pass.

### P5 — every property requirement counts its reads

`MockVar.mockImpl`'s stored branch is gone. Every property requirement that is not
`/// sourcery: handler` now emits the accessor pair over `_<var>`, and
`MockGenerator.swift`'s initializer assigns `MockNaming.store($0.mockedVariableName)` while its
parameter keeps the requirement's own name — so `Mock(themeProvider:)` is unchanged and construction
moves no counter.

**One rule §2.5 did not state, decided here against a measurement: the witness stays settable
wherever it is settable today.** A read-only requirement backed by a `var` store was emitted as a
settable stored property (`var recordPermission: RecordPermission`), and
`skills/swift-sourcery-mocks/references/generated-api.md:139` documents that as the way a test
re-seeds it. Making every read-only witness get-only broke three assignments in this repository's
own `Tests/Checks/Behaviour/Main.swift` — `recordPermission` at `:45` and `installationId` at `:110`
and `:422` — with `cannot assign to property: … is a get-only property`, which is what §5's claim
that the property change is "additive: nothing that compiles against those mocks today stops
compiling" would have cost. The emitted rule is therefore:

| requirement | witness | `<var>SetCount` |
| --- | --- | --- |
| `{ get set }` | `get` + `set` | counted on write |
| `{ get }` | `get` + `set` | not emitted — a re-seed was uncounted before and stays uncounted |
| `{ get }`, `/// sourcery: const` | `get` only, `let _<var>` | not emitted |
| `{ get }`, `/// sourcery: handler` | `get` only, no store | not emitted |
| `{ get set }`, `/// sourcery: handler` | `get` + `set`, no store | counted on write |

Isolation carries through unchanged: `nonisolated var installationId` on the accessors,
`nonisolated(unsafe) var _installationId` on the store and the counters
(`Snapshots/Mocks.generated.swift:225-238`).

Recorded diff: 408 added lines, 46 deleted. 27 property members gained `GetCount` — the snapshot
went from 8 to 35 — against §5's estimate of 21, the difference being the properties `Naming.swift`
and `Properties.swift` added in P2 and P4.

`Tests/Checks/Behaviour/Main.swift` gains `checkPropertyCounting`, 11 assertions: construction
counts no read, two reads count two, a seed through `_<var>` counts none, a write to a `{ get set }`
requirement counts a write and no read, the value written is the value read, a seed through the
store counts no write, and `<var>GetHandler` wins over the store while leaving it alone.

The collision gate gains the two cases this phase's new names create: a protocol declaring
`draftGetCount` beside `draft`, which was not a collision before (`GetCount` reached only computed
getters), and one declaring `_draft`, which is the name D9 chose. Four cases now.

**`kotlin-ksp-mocks` adopting §2.5 is not a no-op, and `SetCount` is not what divides the two
generators.** Re-read at `MockRenderer.kt:127-140`: its stored branch emits `SetCount` for a mutable
property and nothing at all for a read-only one — no counter, no handler, no store — while its
`GetCount` / `GetHandler` pair exists only on the `isReadOnlyFlow` branch (`:109-123`). Swift emitted
`SetCount` for a mutable stored property before this spec and still does, so the two have always
agreed there. What that processor would have to adopt is `GetCount`, `GetHandler` and the store on
every property requirement. §8's closing note stands.

Gates: `run-checks.sh`, diff read, then `--record`; both language modes clean; behaviour checks
pass; `Tests/Examples/ExampleProjectSpm/test-ios.sh` 19 tests, 0 failures, including
`UploadProgressingMock, progressGetCount == 0`, which reads a publisher property's counter this
phase leaves to P7.

### P6 — an effectful property requirement generates the accessor it declares

`MockVar` reads `variable.isAsync` and `variable.throws` into `effectsDecl` (` async`, ` throws`,
` async throws`) and `effectfulCallDecl` (`try `, `await `), and writes both into the accessor, into
`<var>GetHandler`'s type and into the call that consults it. `PropertyEffectfulMock.config` emits
`get async throws`, `configGetHandler: (() async throws -> String)?` and
`return try await handler()`.

A new `accessor(getter:setter:)` builds the witness in one place: a bare getter body where there are
no effects and no setter, `get` / `set` blocks where there is a setter, and a `get\(effectsDecl)`
block where there are effects — a bare body cannot carry `async` or `throws`. It serves the
smart-default branch too, so an effectful publisher property would carry its effects through the
same code, though no fixture declares one.

An effectful requirement is get-only: Swift has no effectful setter, so `hasSetter` is false
whenever `hasEffects` is true, and no `<var>SetCount` is emitted. `_<var>` stays assignable, which is
how `PropertyEffectfulMock(loader:)`'s value is re-seeded.

**Typed throws are refused on both paths, which §2.6 chose and P6's plan mentioned only for the
property.** `MockVar.mockImpl` throws `MockError.typedThrowsUnsupported` when
`variable.throwsTypeName` is non-nil, and `MockMethod.from` does the same over
`method.throwsTypeName` — the method path writes bare `throws` at `MockMethod.throwingDecl` and had
the identical defect. The message names the protocol, the member, the error type and the fix.

Measured on Sourcery 2.3.0, which is what `Scripts/engine-pin.sh` pins, over a probe declaring all
five shapes:

| declaration | `isAsync` | `throws` | `throwsTypeName` |
| --- | --- | --- | --- |
| `var plain: Int { get }` | false | false | nil |
| `var a: Int { get async }` | true | false | nil |
| `var t: Int { get throws }` | false | true | nil |
| `var at: Int { get async throws }` | true | true | nil |
| `var typed: Int { get throws(ProbeError) }` | false | true | `ProbeError` |
| `func mTyped() throws(ProbeError) -> Int` | — | true | `ProbeError` |

So `throws` alone cannot distinguish a typed throw from an untyped one, and `throwsTypeName` is what
both refusals test.

`Tests/Checks/Fixtures/Properties.swift` gains `PropertyEffectful`: `{ get async throws }`,
`{ get async }`, `{ get throws }`, a plain sibling, and one `{ get async }` requirement with no
synthesizable default so the initializer seeds an effectful member's store.
`Tests/Checks/Behaviour/Main.swift` gains `checkEffectfulProperties`, 6 assertions: an `{ get async }`
accessor suspends and returns the store and counts the read, an `{ get async throws }` handler's
error propagates out of the accessor while the read that threw is still counted, a `{ get throws }`
accessor returns the store, and seeding an effectful requirement's store counts no read.

The `collision` gate is renamed **`refusal`** and gains the two typed-throws cases — the gate is
every construct the templates refuse to emit, not only colliding names. Six cases.

Gates: `run-checks.sh`, diff read, then `--record` — 74 added lines, no deleted line; both language
modes clean; behaviour checks pass; `Tests/Examples/ExampleProjectSpm/test-ios.sh` 19 tests, 0
failures. P8 deletes `CONTRIBUTING.md` §"Open items"'s effectful-property entry, which this phase
closes, and adds typed throws in its place.

### P7 — the publisher construct, and what a stream member records

`SourceryRuntimeExtensions.smartDefaultValueImplementation` now returns
`(getterImplementation: [SourceCode], mockedVariableHandlers: [SourceCode], suppliesHandlerConsultation: Bool)`
and takes `recordsStreamValues`. The third element is what lets the publisher branch own the handler
read: `MockVar` emits its own `if let handler = <var>GetHandler` only when the branch does not, so
the handler is consulted once, at subscribe time (§2.7), rather than twice at two different moments.

**The `AnyPublisher` branch emits §2.7's construct verbatim**, in the property form (the
`<var>GetHandler` read inside the `Deferred` closure) and the method form (only the subject fallback
deferred; `<method>Handler` stays at call time, where its arguments are). Nine members per publisher
requirement, in the order §2.7 lists them.

**The `AnyObserver` branch gains `<name>Events: [Event<Element>]`**, appended between the counter and
the handler — the order `<method>CallCount` / `<method>Args` / `<method>Handler` already sets, so a
handler that traps does not un-make the event.

`SourceCode` gains one property, `trailer`: text emitted immediately after a block's closing brace.
It is what lets `handleEvents(receiveOutput: { … }, receiveCompletion: …, receiveCancel: …)` be
built as a block rather than as a hand-indented multi-line string literal, which is how the `Single`
branch's body is written and why that body carries hardcoded leading spaces. The `Deferred`, the
`.handleEvents(…)` and the `.eraseToAnyPublisher()` are three siblings at one level — Swift parses a
leading-dot line after a closing brace as a continuation.

`AnnotationRegistry.skipArgumentRecording`'s target widens to `Protocol / method / variable` and its
effect names all three arrays; `Scripts/render-annotations.sh --write` re-rendered `README.md`,
`SKILL.md` and `references/writing-testable-protocols.md`. On a method the opt-out already excluded
generics, and `<method>Outputs` takes that exclusion too, for the same reason: the element type would
name the method's generic parameters and a stored property can only name the class's.

**One refusal §2.7 implies and does not state.** An `AnyPublisher` requirement declared `{ get async }`
or `{ get throws }` cannot carry its effects into a synchronous `Deferred` closure, and before P7 it
emitted an accessor whose effects the subject erase satisfied by accident. `MockVar` throws
`MockError.effectfulStreamRequirement` naming the protocol, the member and the two ways out. The
`refusal` gate carries it as a seventh case.

Fixtures: `Streams.swift` gains `FrameStreaming` (a recording member, an opted-out member and an
opted-out method) and `FrameRetaining` (the opt-out on the type).
`Tests/Checks/Behaviour/Main.swift` gains `checkPublisherCounting`, 22 assertions — every check §2.7
records as measured, run against the emitted shapes rather than against a scratch file:

reading counts a read and no subscription; subscribing counts a subscription; a send with nobody
subscribed counts no output; a delivered value counts one and is recorded; one send to two
subscribers counts twice; a completion is counted per subscription; an open subscription counts no
cancel and `cancel()` counts one; a handler seeded *after* the publisher was captured decides the
stream, and its values and its completion are counted; `<name>OutputHandler` sees each value and can
send the next from inside itself, with the recorder holding both; a method's handler still answers at
call time and bypasses the deferred subject entirely; the stream still delivers after the mock is
released; and `skipArgumentRecording` suppresses the recorder while leaving the counter and the
output handler working.

`Tests/Examples/ExampleProjectSpm`'s `SwiftSourceryTemplatesMocksSpec` gains the assertion §1.9
measured a consumer giving up on — `expect(sut.entityObserverEvents.compactMap(\.element)) ==
["next element"]` beside the existing `entityObserverEventCallCount` assertion, on the same pushed
value.

Gates: `run-checks.sh`, diff read, then `--record` — 353 added lines, 25 deleted; both language
modes clean; behaviour checks pass; `run-annotation-checks.sh` and `run-skill-checks.sh` pass after
the re-render; `Tests/Examples/ExampleProjectSpm/test-ios.sh` 20 tests, 0 failures.

### P8 — the documents

Each document states the rule for its own reader, and none re-derives another's reasoning.

- **`SKILL.md`** — §2.1 in one sentence, §2.2 in four, and the §2.3 table rebuilt with an "on"
  column: `_<var>`, the four publisher counters, `<name>Outputs` / `<name>OutputHandler`,
  `<name>Events`, and **`Dispose*` on its own row beside `Cancel*`**, which is `:202`'s correction —
  that line documented `<method>CancelCallCount` for both return types. Three sentences follow for
  §2.5's property members, §2.6's effectful accessor and §2.7's subscribe-time handler. 282 lines
  against the 400-line ceiling.
- **`references/generated-api.md`** — the naming rule at the top, the full overload chain including
  step 4, §1.4's refinement case with `methodName` named as the answer, §2.5's property shape with
  `const` and `handler`, §2.6's effectful accessor, `Cancel*` and `Dispose*` against their own return
  types, and the twin table gaining a second table of the rows the two generators do **not** share.
- **`references/stream-members.md` is new.** The publisher and RxSwift material did not fit: with
  §2.7's shape written out, `generated-api.md` reached 337 lines against a 250-line ceiling
  (`AGENTS.md` §"The skill is for adopters"). Splitting is the better half of the trade — a
  reference costs nothing until the agent opens it — so the stream shapes, the four counters, the
  late-seeded handler, the delivery-not-sending rule and the `AnyObserver` recorder live in their
  own 89-line file, and `generated-api.md` (249) carries a five-line summary and a link. P8's plan
  assumed one file; it is now two.
- **`references/troubleshooting.md`** — three new sections: `has no member '<name>'` (§2.1 and
  §2.2, including that a refinement can move a name), a property read count that moved because the
  test read the property rather than `_<var>` (§2.5), and `<name>SubscribeCount` at zero (§2.7,
  with delivery-not-sending and the method-handler-bypasses-the-subject case).
- **`README.md`** §"Generated Mock API" — the rule and the full §2.3 suffix table, with
  `MockNaming.swift` named as where every name is built; two new key-feature bullets for §2.5 and
  §2.6. §"Combine" — a table of which counter answers which question, the subscribe-time handler,
  the `skipArgumentRecording` opt-out and the effectful-publisher refusal. What the subject is and
  what `subject = "CurrentValue"` does is unchanged, and says so.
- **`CONTRIBUTING.md`** — §"Where to change what" gains "A mock member's name", naming
  `MockNaming.swift` and the fact that the uniqueness check reads names back out of the emitted
  declarations, so a new member is covered without being enumerated. §"Design rules already decided"
  gains three rules (§2.1–§2.2, §2.5, §2.6) and the publisher entry is **amended rather than
  replaced** — the subject and its default are unchanged and what is added is the construct around
  them. §"Open items" loses the effectful-property entry, which P6 closed, and gains typed throws
  and `AnySubscriber` (§8 questions 1 and 4).
- **`AGENTS.md` / `CLAUDE.md`** §"State a rule once" — one bullet naming `MockNaming.swift`, kept
  byte-identical with `cp`.
- **`Tests/Evals/member-names`** — the sixth case. It asks which members a mock gives for
  `setting4_2`, `pageSize`, `perform1_0()`, `ID()` and a three-way `end` overload group, with the
  generated file deliberately out of reach. Five graders: the skill fired (with-arm only), the
  prefix is verbatim (failing on `perform10CallCount`, `iDCallCount` or one rule for methods and
  another for properties), the overload names (failing on `endAtFieldValuesCallCount` — the label
  *and* the name — or on the plain name going to the wrong overload), the property members (failing
  if a read-only requirement is said to generate none), and a regex for `perform1_0CallCount`. The
  five-prompt count in `AGENTS.md`, `CONTRIBUTING.md` and `Tests/Evals/README.md` is now six.

**Not done here, and why.** `kotlin-ksp-mocks/skills/kotlin-ksp-mocks/references/generated-api.md`'s
twin table is a change to another repository, which P8 itself records as "a follow-up in that
repository". The Swift-side half of that pair — the table naming the rows the two generators do not
share — is in `references/generated-api.md` as of this phase, so the two tables are out of step
until that follow-up lands. See the P9 amendment below.

Gates: `run-skill-checks.sh` (SC5 at 282 / 249 / 89 lines, SC8 every link resolves, SC9 no version
literal — a first draft of the troubleshooting entry named the release the transform changed in and
SC9 caught it, SC13 six cases and 23 graders), `run-annotation-checks.sh` after the re-render, and
`run-checks.sh`.

### P9 amendment — re-align the Kotlin twin before the tag

Superseding §4 P9's ordering, and recorded here because it was decided while P8 was being written:
**the two repositories are brought back into step before this change is tagged**, not after. What
that covers, and what each repository owes:

1. `kotlin-ksp-mocks`' twin table gains the rows this side now names (P8's list above) — the
   stored-property read counter, the publisher counters and recorders, and `<method>EventCallCount`
   for an `AnyObserver` member, none of which either table carried before (D11).
2. Whether `kotlin-ksp-mocks` adopts §2.5 — `GetCount`, `GetHandler` and a backing store on every
   property requirement rather than `SetCount` alone (`MockRenderer.kt:127-140`, re-measured in
   §9's P5 entry) — is decided before the tag rather than left open. If it does not, both twin
   tables say so in the same words.
3. `CHANGELOG.md`'s entry names the state of the twin as of the tag, so a consumer testing the same
   logic on both platforms reads one answer rather than inferring it from two tables written at
   different times.

The rest of §4 P9 stands: the entry's three headings, the consumer delta from §5 measured into it,
and the entry written before the tag.

### P9 — the CHANGELOG entry, and the consumer measured

`CHANGELOG.md` gains an `## Unreleased` entry under the three headings that file's header states,
above the annotation-name entry and shipping in the same release as it. **Generated output** carries
the two rename categories with before/after, §2.5's property members, §2.6's accessor, §2.7's
construct and counters, and the two diagnostics that replace silent failures. **Breaking** carries
the consumer table below and the reason no deprecated aliases are emitted — the generator would have
to keep both naming rules to know the old name, which is the condition D6 removes. **Adopting**
carries the two lanes' commands, `_<var>` for a test that reads a mock property, and the publisher
member's new surface.

**The consumer was regenerated, not estimated.** `modaal-firebase-wrappers`' seven modules were
generated from this working tree into a scratch directory — its own tree was left untouched — and
diffed against its committed output at templates 0.2.15.

| measured | §5 predicted | actual |
| --- | --- | --- |
| files, lines | `7 files, 218 insertions` for the bump alone | 7 files, **1706 → 2934 lines**; 274 generated members → 515 |
| §2.1 renames | none | **none** — confirmed; no removed name carries an underscore or leading capitals |
| §2.2 renames | 27 member groups, 15 distinct names | **30 members over 15 declarations** — the 15 names §5 listed, each with a `CallCount` and a `Handler`; §5's "27 member groups" counted groups, not members |
| §2.5 additions | 73 property members | **168 members over 56 requirements** — `GetCount`, `GetHandler` and `_<var>` each. §5's 73 is the number of `<method>Args` arrays the version bump adds, which its script evidently counted instead |
| §2.3, §2.4, §2.6, §2.7 | none | **none** — confirmed |
| its own tests that stop compiling | 9 references in 2 files | **9 references in 2 files** — `setDataDataForDocumentDocumentMerge*` (4), `setDataDataForDocumentDocumentMergeFields*` (4), `signInWithEmailEmailPasswordCompletionHandler` (1) |

So §5's two errors are in the same direction and both under-count: it read member *groups* where the
entry reads members, and it attributed the version bump's `Args` arrays to §2.5. The rename surface
it predicted — which declarations move, and which of the consumer's own tests break — is exact.

**Not done, and it is the gate on the tag.** The tag is not cut, and per the P9 amendment above it
cannot be until `kotlin-ksp-mocks` is brought into step: its twin table, and the decision on whether
it adopts §2.5. `CHANGELOG.md`'s entry names where the rule is stated and where it is built; the
sentence naming the state of the twin as of the tag is written when that decision is taken.

Lanes run at this phase, all green: `run-checks.sh`, `run-skill-checks.sh`,
`run-annotation-checks.sh`, `run-cli-checks.sh`, `run-plugin-checks.sh`, and
`Tests/Examples/ExampleProjectSpm/test-ios.sh` at P7. `run-xcode-checks.sh` was not run.

---

## 10. Proposed: making a non-derivable name readable in the file, and finding the file

Proposals only. Nothing here is implemented, and P1–P9 are complete without it. Two questions, asked
after P9: how an agent reading a generated file learns that a member's name is not its declaration,
and how an agent finds that file at all on the plugin lane.

### 10.1 What is left after P8, measured

§2.1 and §2.2 make most names derivable, and P8 states the rule in `SKILL.md`, `README.md` and
`references/generated-api.md`. Three cases stay underivable **from the declaration a reader has in
front of them**, even knowing the rule:

1. **An overload's long form** (§2.2 step 2). Whether a declaration is in an overload group at all
   depends on the mock's whole requirement set, inherited requirements included, so a protocol
   refining another can put a requirement into a group that neither declaration shows (§1.4, §3 D3).
2. **The return-type discriminator** (§2.2 step 3). `dataStringAnyOptional` appears in no
   declaration.
3. **`/// sourcery: methodName = "…"`**, which is visible at the declaration but not at the mock.

Counted over generated output as of P9:

| | methods | prefix ≠ declared name | classes with at least one |
| --- | ---: | ---: | ---: |
| `Tests/Checks/Snapshots/Mocks.generated.swift` | 56 | **4** (7%) | 4 of 33 |
| `modaal-firebase-wrappers`, regenerated (7 modules) | 152 | **47** (30%) | 10 of 34 |

The consumer's are concentrated: `CollectionReferenceProtocolMock` 12, `QueryProtocolMock` 11,
`CloudFileStoringMock` 6, `CloudStorageReferencingMock` 6, then six classes with three or fewer. A
query-builder API overloads heavily, and that is where an agent's derived guess is wrong 30% of the
time.

**Property prefixes need nothing.** `MockNaming.variablePrefix` is the declared name minus backticks
in every branch, so no property name is underivable and no property comment is proposed.

All three causes are known to `MockMethod` at emission — `useShortName`, `useReturnTypeInName` and
`annotatedMethodName` — so no new analysis is needed to write the comment.

### D14 — where the naming rule is stated inside a generated file

**Ruled (a) and (b) — §10.5.**

- **(a) One header per file, under the Sourcery banner (recommended).** Four lines stating §2.1 and
  naming the overload exception. Cost is O(files): 28 lines across the consumer's seven.
- (b) One header per class, under the existing `// MARK: - <Protocol>` line. In view wherever an
  agent lands, at O(classes): 34 headers in the consumer, ~170 lines.
- (c) Nothing; the rule is in `SKILL.md` and `README.md` as of P8. Leaves an agent reading a
  generated file with no statement of the rule in the file it is reading.

(a) and (b) differ only in whether the statement is in view when an agent reads a slice of a large
file rather than the whole of it. The consumer's regenerated output is 2934 lines, which is read in
slices; that is the case for (b), and D15(b) covers it more cheaply.

### D15 — how a name that is not the declaration is recorded

**Ruled (c) — §10.5.**

- **(a) One comment line above the witness, naming the selector, the prefix and the cause
  (recommended).** Emitted only for the three cases in §10.1, so most members get nothing:

  ```swift
  // `end(at:)` members are named `endAt*` — overload of `end`, argument labels appended
  func end(at fieldValues: [String]) {
      endAtCallCount += 1
  ```

  ```swift
  // `data()` members are named `dataStringAnyOptional*` — overload of `data` differing only in return type
  // `refresh()` members are named `reloadNow*` — `/// sourcery: methodName = "reloadNow"`
  ```

  The line carries both spellings, so `grep "end(at:)"` and `grep endAt` each find it. Cost: 47
  lines in the consumer (1.6% of 2934), 4 in the snapshot.
- (b) A per-class index line instead, listing the class's non-derived names under the `MARK:`.
  Ten lines in the consumer, one per class that has any, and in view on landing — but a line listing
  12 mappings is long, and it is not beside the declaration it describes.
- (c) Both (a) and (b). 57 lines in the consumer; the index is then a second statement of what the
  per-member lines already say.
- (d) Neither. An agent that guesses `endAtFieldValues` gets a compile error naming the member it
  wrote, and finds the real name by reading the class — which is what the evaluation measured as the
  cost.

### D16 — how the comment is kept true

**Ruled (a) and (b) — §10.5.**

The comment is a claim about the name, so it must be produced by the function that produces the
name. `MockNaming` gains one function taking the same three inputs `methodPrefix` takes and
returning the comment or `nil`; `MockMethod` calls it where it already calls `methodPrefix`. Written
at the emission site instead, it becomes a second statement of the rule, which is what `AGENTS.md`
§"State a rule once" exists to prevent and what §1.8 measured the cost of.

- **(a) Generate it from `MockNaming`, and let the snapshot be the gate (recommended).** A comment
  that disagrees with the name below it cannot be produced, and the snapshot diff shows both.
- (b) The same, plus a check in `run-checks.sh` asserting that each comment's stated prefix equals
  the `CallCount` on the following lines, with a red control. Cheap — one pass over the snapshot —
  and it gates a hand-edit of the template that (a) makes impossible by construction.

### 10.2 When this should land, if it lands

**In the same release as P1–P9.** It changes every generated file, so a consumer regenerates and
re-fingerprints either way; landing it in this tag costs nothing beyond the regenerate already
required by §2.1 and §2.2. Landing it later forces a second regenerate of every consumer, and a
second `mock-templates validate` failure, for comments alone.

### 10.3 Finding the generated file on the plugin lane

Measured on this machine — both lanes write under one path segment,
`SourcerySwiftCodegenPlugin/.generatedFiles/`:

```
# SwiftPM
<build>/plugins/outputs/<package lowercased>/<Target>/destination/
    SourcerySwiftCodegenPlugin/.generatedFiles/<Config stem>/<Template>.generated.swift

# Xcode
<DerivedData>/<Project>-<hash>/Build/Intermediates.noindex/BuildToolPluginIntermediates/
    <project>.output/<Target>/SourcerySwiftCodegenPlugin/.generatedFiles/<Config stem>/<Template>.generated.swift
```

So one command finds them on either lane, given the build root:

```bash
find "$BUILD_ROOT" -path '*/SourcerySwiftCodegenPlugin/.generatedFiles/*' -name '*.generated.swift'
```

`$BUILD_ROOT` is `.build` for a SwiftPM package. For an Xcode project it is derived data, which may
be relocated, so it is read rather than assumed:

```bash
xcodebuild -project X.xcodeproj -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILD_DIR = /{print $2}'
```

### D17 — what to do about it

**Ruled (a) and (a2) — §10.5. (f) was not ruled and is not in P11.**

- **(a) Document it, in `references/spm-plugin.md` (recommended).** A "Finding the generated file"
  section carrying the two path shapes, the `find`, and the `xcodebuild -showBuildSettings` line.
  No build change, and it works against every version already released.
- **(a2) …and document the build-log route beside it (recommended, same section).** The plugin
  already emits the absolute directory:
  `Diagnostics.remark("<config>: the plugin supplied output: <abs path>")`
  (`Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift:529-550`). It is in every
  build log today and is documented nowhere. `references/troubleshooting.md` already tells a reader
  to read that log for a missing type (`spm-plugin.md:162`); this is the same log and one more thing
  it answers.
- (b) The skill instructs the adopting repository to commit a three-line
  `Scripts/find-generated-mocks.sh` once, so later sessions run one command rather than
  reconstructing the `find`. Durable across agent sessions; it is a file in the consumer's repository
  that this repository cannot update.
- (c) A **command plugin** — `swift package plugin generate-mocks
  --allow-writing-to-package-directory` — writing the generated files into the package tree. A build
  tool plugin cannot: its commands are sandboxed to `pluginWorkDirectory`. A command plugin can.
  **Not recommended:** `mock-templates generate` already writes committed, in-tree, greppable output
  and is the documented lane for exactly that (`references/cli-lane.md`), so this adds a second route
  to the same result. Worth revisiting only to reuse the plugin's config discovery.
- (d) A symlink or pointer file written into the package directory by the build tool plugin.
  **Impossible**, on the same sandbox fact as (c).
- (e) Emit the absolute output path into the generated file's own banner. It answers "where did this
  come from" for a reader who already has the file, which is not the question asked.

**(f) State the discoverability difference where a consumer picks a lane.**
`references/cli-lane.md` and `references/spm-plugin.md` compare the two on fingerprinting, CI and
checkout size. Generated output that is committed and greppable at a stable path, against output
under a derived-data path that has to be found, is one more line in that comparison, and it is the
line that matters for a repository whose tests are written by agents.

### 10.4 Phasing, if this is taken

**P10 — the comments (D14, D15, D16).** `MockNaming` gains the header text and the per-member
comment function; `MockMethod` calls the second where it calls `methodPrefix`; `MockGenerator` emits
the header. Fixtures already cover all three causes — `NamingOverloads` (§2.2 step 2),
`ReturnTypeOverload` in `Tests/Examples/` and the `data()` pair (step 3) — and a `methodName` fixture
is added, which the tree does not have today. Gates: the snapshot diff, both language modes, and the
example lane, which is where the return-type-discriminated names are asserted on.

**P11 — the plugin-output documentation (D17).** `references/spm-plugin.md` gains the section;
`references/troubleshooting.md` gains a "the generated file is not where I looked" entry; the
lane-comparison line in D17(f) goes in both references. `SKILL.md` gets one line, in its body, with
the `find`. No template change, so no snapshot moves.

P10 belongs in this release (§10.2). P11 is independent of the tag and can land at any point.

### 10.5 Ruled

Ruled 2026-09-12. The options listed in D14, D15, D16 and D17 stand as written; this section names
which of them are taken, and supersedes the `(recommended)` mark in each of those four sections
where the ruling differs from it.

| decision | taken | against the mark in that section |
| --- | --- | --- |
| D14 — where the rule is stated in the file | **(a) and (b)** — a header at the top of the file *and* one under every class's `MARK:` line | (a) alone was marked |
| D15 — how a renamed member is recorded | **(c)** — the per-class index *and* the line above the witness | (a) alone was marked |
| D16 — how the comment is kept true | **(a) and (b)** — generated from `MockNaming`, *and* asserted by a gate in `run-checks.sh` with a red control | (a) alone was marked |
| D17 — finding the generated file on the plugin lane | **(a) and (a2)** — the path shapes and the `find` in `references/spm-plugin.md`, and the build-log remark beside them | as marked |

D14(b) is taken for the fact D14 records against it: a 2934-line generated file is read in slices,
and the per-class header is what puts the rule in the slice an agent lands in. The class header is
the same two lines for every class, with nothing interpolated from the protocol, so the snapshot
diff a new protocol produces is those two lines and the class.

D15(c) states the same sentence in two places — above the witness and in its class's index — and
both come from one call, so the two cannot disagree.

D16(b) gates what D16(a) makes impossible by construction. What it catches is a later edit that
writes a comment where a member is emitted instead of asking `MockNaming` for one, which is what
`AGENTS.md` §"State a rule once" forbids and what no other check reads. The gate also asserts that a
class's index and its witness lines are the same set, so a member commented in one place and not the
other fails the run.

**Not taken:** D17(b), (c), (d) and (e), each for the reason D17 gives. **Not ruled:** D17(f), the
lane-comparison line for `references/cli-lane.md` and `references/spm-plugin.md`. It is out of P11's
scope and stays open.

**What this makes P10 emit, against §10.4's two items:** four — the file header (D14a), the class
header (D14b), the class index (D15b), and the line above the witness (D15a) — plus the gate (D16b)
and its red control. `MockGenerator` emits the first three, `MockMethod` the fourth, and every
string comes from `MockNaming`. The `methodName` fixture §10.4 names is still added, because no
fixture in the tree carries that annotation today.

---

## 11. What landed: P10 and P11

### P10 — the naming comments, and the gate that reads them back

`MockNaming` gained `MethodPrefix`, a second `methodPrefix` overload returning it, the two comment
line spellings, the index header and the two header blocks. `MockMethod.mockedPrefix` calls it once
and `mockedMethodName` reads `.prefix` off the result, so the name and the comment come from one
call. `MockGenerator` emits the file header, the per-class header and the class's index;
`MockMethod.mockImpl` emits the line above the witness.

**What decides that a comment is written is the prefix against the declared name, not which branch
produced it.** `useShortName: false` on a method with no parameters appends nothing, so the flags
would have claimed a rename that did not happen; `/// sourcery: methodName` may also repeat the
declared name. Both cases are `prefix == declaredName` and get no comment.

**Two wordings changed from the drafts in D15.** The return-type cause reads ``overload of `data`
returning `[String: Any]?` `` rather than "differing only in return type": a class whose index holds
both members of such a group would otherwise carry the same line twice, with only the prefix telling
them apart. And `SourceryRuntime.Method.selectorName` is `refresh` for a method that takes nothing
and `end(at:)` for one that does, so `methodPrefix` appends `()` where it is absent — the spelling
the comment carries is then the declaration's in both cases.

Because the return type is what the comment shows, `methodPrefix` takes `returnTypeName:` and
derives the discriminator itself. `MockMethod.returnTypeDiscriminator` is gone; the token in the
name and the type in the comment are now one input.

**Fixtures.** `Naming.swift` gained `NamingAnnotated` (`methodName`, which no fixture carried) and
the `NamingReturnTypeBase` / `NamingReturnTypes` pair, so all three causes are in the fast lane's
snapshot rather than two of them in `Tests/Examples/`. `Tests/Checks/README.md` gained a table for
`Naming.swift` and one for `Properties.swift`, which P2 and P5 added without listing.

**The gate (D16(b))** is `run-checks.sh`'s fifth, `naming-comments`, and the earlier typecheck and
behaviour gates are renumbered 6 and 7. It reads every `` `X` members are named `Y*` `` line out of
the generated file: a line inside a class must sit above a `func` whose first statement is
`<prefix>CallCount += 1`, and each class's index must be exactly the set of lines commented inside it. Two
red controls, both on a copy of the generated file: one renames a prefix in a comment, one deletes
an index entry.

| measured | count |
| --- | --- |
| renamed members in the fixture snapshot | 7 — 4 overload long forms, 2 return-type discriminators, 1 `methodName` |
| lines added to the fixture snapshot | 140, all comments |
| `modaal-firebase-wrappers`, regenerated from this tree | 2934 → **3148 lines**, +214 |
| where those 214 go | 7 files × (1 blank + 5 header), 34 classes × 2, 10 index headers, 47 index entries, 47 witness lines |
| renamed members in the consumer | **47, in 10 of its 34 classes** — §10.1's count, confirmed |
| generated code changed | none — the diff against P9's regeneration is comments and seven blank lines |

`CHANGELOG.md`'s entry takes the new paragraph, the 3148, and a table row for the 214 lines.
`README.md`, `CONTRIBUTING.md` §"Design rules already decided", `SKILL.md`, `references/generated-api.md`
and `references/troubleshooting.md` each state it once. `generated-api.md` was at its 250-line cap,
so two sentences there were tightened to pay for the new one.

### P11 — finding the generated file (D17(a), (a2))

`references/spm-plugin.md` gained `## Finding the generated file on disk`: both lanes' path shapes,
what the config stem is, the `find` over
`*/SourcerySwiftCodegenPlugin/.generatedFiles/*`, the `xcodebuild -showBuildSettings` line for
relocated derived data, and the plugin's own remark naming the directory — which was in every build
log and documented nowhere. `references/troubleshooting.md` gained
`## The generated file is not in the repository`. `SKILL.md`'s plugin lane gained **Finding what it
wrote**, with the `find`.

No template, plugin or CLI change, so no snapshot moved. **D17(f) is not implemented**, per §10.5:
the lane-comparison line was not ruled.

### Lanes

`run-checks.sh` (snapshot recorded after reading the diff), `run-skill-checks.sh`,
`run-annotation-checks.sh`, `run-cli-checks.sh`, `run-plugin-checks.sh` and
`Tests/Examples/ExampleProjectSpm/test-ios.sh` — 20 tests, 0 failures. `run-xcode-checks.sh` was not
run.

**One lane defect found, not fixed and not caused by this phase.** `run-plugin-checks.sh` exits 1 on
a second run without printing a failure: its artifact-bundle section reuses
`$WORK_DIR/bundle-route` as the scratch path (line 489), the warm build does not re-run the plugin,
the remark it greps for is absent, and the `grep -o … | head -1` in that else branch takes the
script down under `set -eo pipefail` before `fail` can name it. Deleting that scratch directory and
re-running is green.

### The skill body against the compaction floor

`specs/002-annotation-registry-and-agent-skill/spec.md` §3.1 records that auto-compaction keeps the
first 5,000 tokens of each loaded skill, and its §15.2 left `SKILL.md` at 250 lines and 13,654 bytes,
reported at **~4.8k on invoke**. P8, P10 and P11 each added to that body. Measured with 002 §15.1's
procedure — `claude plugin marketplace add ./`, `claude plugin install swift-sourcery-mocks --scope
local`, `claude plugin details swift-sourcery-mocks`, Claude Code 2.1.268:

| state | lines | bytes | on invoke |
| --- | ---: | ---: | ---: |
| `master` (002 §15.2) | 250 | 13,654 | ~4.8k |
| P8 | 282 | 16,361 | — |
| after P10 and P11 | 297 | 17,180 | **~6.1k** |
| after the trim | 208 | 13,988 | **~4.9k** |

P8 crossed the floor on its own; P10 and P11 added ~0.3k on top. Always-on is unchanged at ~290 —
the description was not touched, and SC4 reports it at 740 characters.

**Four moves, on 002 §15.3's pattern: material a reference already carries in full leaves the body.**

1. The CLI `generate` invocation. `references/cli-lane.md` §"The script shape worth copying" has the
   same flags in a loop over modules; the body names each flag and points at it.
2. The `protocol DataService { … }` snippet and the external-protocol extension block.
   `references/writing-testable-protocols.md` §"What to annotate" carries both.
3. The `## Publishers are subject-backed` section, folded into §"What the generated mock gives a
   test" as the two-line subscribe-then-send example plus the `PassthroughSubject` rule. The
   paragraph on when a publisher's handler is read went with it —
   `references/stream-members.md` states both, and the body's link now says so.
4. `## When it goes wrong` re-formed from a three-column table to a list of the same nine entries,
   which drops the column scaffolding.

The rest is prose compression. No instruction was removed, every one of the nine `mock-templates`
flags is still named (SC7), every reference is still linked at its point of need (SC8), and the
block between the annotation markers was not touched (AC6 reports all three rendered blocks
current). All thirteen skill checks pass.

**Measurement cleanup.** The install reads the working tree, so it was made local-scope and then
undone: plugin uninstalled, marketplace removed, and the `.claude/settings.local.json` the local
install wrote deleted. State before and after: one marketplace (`claude-plugins-official`), no
local plugin.

**The third sighting of the gap 002 §15.6 names.** No check measures the token budget: SC5 counts
lines, 400 for the body, and 002 §15.6 records the line budget passing on both occasions the token
budget was breached — ~5.1k at 258 lines, ~5.5k at 273 lines. This is the third: SC5 passed at 297
lines while the body was ~1.1k over the floor, and nothing in CI said so. `claude plugin details` is
still the only thing that reads the figure, and it needs `claude` and an install on the runner —
which is the reason 002 §15.6 gives for `run-skill-checks.sh` not doing it.

---

## 12. Aligning with `kotlin-ksp-mocks`: what its §11 and §12 ask of this repository

Read on 2026-09-12 from
`/Volumes/DATA01/Projects/kotlin-ksp-mocks/specs/002-property-accessors-and-stream-counters/spec.md`
§11 and §12. That section was written against this branch at `c332601` — its P1 to P11 — and rules
four decisions on its own side: **D15 (c), D16 (a), D17 (a), D18 (c)**. Its §12.3 hands four items
to this repository.

This section extracts those four, states each against the current tree with the line numbers checked
here, adds what they cost measured on this repository and on `modaal-firebase-wrappers`, and
proposes D18 to D21. **Nothing here is implemented and nothing is ruled.** §9's P9 amendment makes
the Kotlin re-alignment the gate on the tag; this is that work in progress, not its close — the gate
lifts when D18 to D21 are ruled and whatever they take has landed.

### 12.1 What the comparison confirms

Its §11.1 reports the two generators agreeing on every member name a test writes — `CallCount`,
`Args`, `Handler`, `GetCount`, `GetHandler`, `SetCount`, `_<prop>`, the six stream words — and on
the `"<fn>Handler expected to be set."` string, which is §2.4's wording byte for byte. Four shapes
agree beyond the names: the property accessor's statement order and the order its members are
emitted in, the stream member order, the overload long form, and refusing generation on a collision
by reading the names back out of the emitted declarations. `<name>Subject` against `<fn>Channel` is
the one name that differs by decision, as §9's twin table already records.

### 12.2 The four items its §12.3 hands here

**1. The twin table is stale in three rows** (`references/generated-api.md:226-245`). It describes
that processor as it was before its P1 to P3, and `run-skill-checks.sh` reads this repository's
renderer and not that one, so nothing goes red on it. Their §12.3 item 1 gives the replacement rows:
`<var>GetCount` / `<var>GetHandler` map to `<prop>GetCount` / `<prop>GetHandler` **on every
property**; `<var>SetCount` to `<prop>SetCount` on a `var` requirement; `_<var>` to `_<prop>`; and
the six stream members map across on a `Flow`-returning function or a read-only `Flow` property. Two
rows leave the "no counterpart" table — `:241` and `:242` — and the `AnyObserver`,
`AnyCancellable` / `Disposable` and per-declaration-annotation rows stay. Two prose claims move with
them: `references/generated-api.md:131-132` ("a read-only requirement's witness is still settable")
and `CONTRIBUTING.md:242-243` ("The witness stays settable wherever it was settable before that
change"), both of which state the rule item 2 replaces.

**2. D15 (c) — the witness of a `{ get }` requirement becomes get-only.** Their D2 (a) emits
`override val` and keeps `mock._<prop> = value` as the seed path; ruling (c) asks this side to
match, so that **`mock._<prop> = value` is the only assignment that seeds a read-only requirement,
and it is the same expression on both platforms** (their §12.4). The edit is two lines:
`MockVar.swift:178` becomes `let hasSetter = !hasEffects && variable.isMutable`, and the
`if variable.isMutable && hasSetter` guard at `:195` reduces to `hasSetter`. `const` and `handler`
are already get-only and do not move; the store stays `var _<var>` for everything but `const`.

What it supersedes here is not §2.5 — §2.5 never stated it — but the rule P5 decided against a
measurement, in §9's P5 entry: "the witness stays settable wherever it is settable today", the table
under it, and the comment at `MockVar.swift:167-177` recording why. Their §12.4 argues the break
lands only on code holding the concrete `<Type>Mock`: a `{ get }` requirement exposes no setter
through an existential or a generic parameter, so nothing assigns one through the protocol.
Measured in §12.3.

**3. Wrap a method's handler-supplied publisher** (their §12.3 item 3, their §9 and D6). A method
returning `AnyPublisher` returns the handler's publisher before the `Deferred` / `handleEvents`
chain — `Snapshots/Mocks.generated.swift:441-455` is the emitted shape — so a seeded method stream
moves no `SubscribeCount`, `OutputCount` or `CompletionCount`, while the property branch reads its
handler *inside* the `Deferred` and is counted. Their §2.3 wraps both. Ruled on neither side.
Combine counts a subscription inside the `Deferred` closure, so adopting it means giving the
handler's publisher a `Deferred` of its own —
`Deferred { self?.<name>SubscribeCount += 1; return handler(args) }` — ahead of the existing chain.
Until it lands, `<name>OutputCount` means "values delivered" on both platforms for a property and
for a channel-backed method, and "values delivered by the subject only" for a handler-seeded method
here.

**4. The record 004 owes.** Under this repository's append-only rule it goes in a follow-up file
beside 004 rather than into the sections it corrects: §8's closing paragraph ("Until it lands, its
stored-property branch emits `SetCount` alone") and P8's row for that repository's
`references/generated-api.md` are both superseded by its P1 to P4, and D15 (c) supersedes the
settable-witness rule P5 decided.

### 12.3 What D15 (c) costs here, measured on 2026-09-12

Their §12.4 leaves the consumer count unmeasured. It is measured here against the output this branch
generates at `c332601`. A witness that loses its setter is one whose `set` block carries no
`<var>SetCount` — a read-only requirement backed by a store:

| | witnesses that become get-only | `{ get set }` witnesses, unaffected |
| --- | ---: | ---: |
| `Tests/Checks/Snapshots/Mocks.generated.swift` | **23** | 5 |
| `modaal-firebase-wrappers`, 7 modules regenerated | **69** | 4 |

What stops compiling, by grep for an assignment to one of the 52 distinct names those 69 witnesses
carry, over that repository's `Tests/` and `Examples/`:

| | sites | where |
| --- | ---: | --- |
| `modaal-firebase-wrappers`' own tests | **12** | `FirebaseAuthCombineTests` (4), `DocumentReferenceCombineTests` (4), `QueryDocumentSnapshotProtocolTests` (2), `FirestoreCombineTests` (1), `QueryCombineTests` (1) |
| this repository's `Tests/Checks/Behaviour/Main.swift` | **3** | `recordPermission` at `:45`, `installationId` at `:110` and `:530` — P5 recorded the third as `:422`, before P6 and P7 grew the file |

Every receiver at those 12 sites is a `<Protocol>Mock` — `newDocMock.documentID`, `mock.count`,
`userMock.uid`, `snapshot.documents` — so the grep's one false-positive risk, a non-mock receiver
with a member of the same name, does not occur. Each site becomes `_<var>`.

**One assertion inverts rather than moving.** `Main.swift:46` reads
`expect(mock.recordPermission == .granted, "a read-only requirement is settable on the mock")`. It
is the behaviour-harness form of the rule D15 (c) retires, so it is deleted or rewritten rather than
re-pointed at `_recordPermission`.

**No deprecation window exists.** `@available(*, deprecated)` marks a property and not one accessor,
so a release that keeps the setter and warns on it cannot be written. The change lands as
`cannot assign to property: … is a get-only property` at each site.

### 12.4 Three divergences that ask nothing of this repository

- **The collision diagnostic text** (their §11.2 item 3). Theirs names the two declarations behind
  the name; `MockError.collidingMemberNames` (`MockGenerator.swift:202-209`) names the type, the
  member and `/// sourcery: methodName`, which has no counterpart there. Neither string is part of
  the shared contract — the member names and `"<fn>Handler expected to be set."` are.
- **`skipArgumentRecording` has no counterpart** (their §11.2 item 4, their D9). It turns
  `<var>Outputs` off as well as `<method>Args` here, so this side can generate a stream member that
  counts without recording. §9's twin table already carries the annotation row.
- **D18 (c), keyword-named requirements.** Their §11.3 measured that a Kotlin interface declaring
  ``val `object` `` generates a file that fails the consumer's compile with 48 errors, and ruled
  (c): each language's reserved words stop at its own boundary, and such an interface is the
  adopter's to rename. §2.1's backtick rule here is unaffected — `object` and `in` are ordinary
  Swift identifiers, `func` and `guard` are the reverse.

### 12.5 One divergence neither side has measured

Their §11.2 item 5: inside an overload group both sides order by parameter count first, and then
differ. Here `areInAscendingOrder` (`MockMethod.swift:391-403`) prefers the overload whose first
parameter has no argument label; there, their spec reports `MockRenderer.kt:161-178` ordering by the
joined rendered parameter types. Two overloads with the same parameter count can therefore keep the
plain name on one platform and take the long form on the other. No fixture in either repository
declares such a pair, so neither side has a generated file showing which name it produces.
`Naming.swift`'s `NamingOverloads` is where one would go: `reference(withPath:)` and
`reference(forURL:)` already have equal parameter counts, but both carry labels, so they exercise
the fallback rather than the tie-break. D21.

### 12.6 Decisions this section proposes

**D18 — does a `{ get }` requirement's witness become get-only?**

**Ruled (a) — §12.8.**

- **(a) Adopt D15 (c) (recommended).** `mock._<var> = value` becomes the one seed path, the same
  expression a test writes on both platforms, and the mock stops offering a setter the protocol does
  not declare. Cost, from §12.3: 23 fixture witnesses and 69 consumer witnesses change shape, 12
  consumer assignment sites and 3 of this repository's own stop compiling, and one behaviour
  assertion inverts. It is a second source break, and this is the release to take it in: a consumer
  is already fixing compile errors from §2.1's renames, and `_<var>` is named in each new one.
- (b) Keep the settable witness and ask the Kotlin side to reconsider D15 (c). Their §11.6 listed
  that as its own option (c) and ruled against it; re-opening it costs a second round and leaves
  `mock.<prop> = value` compiling on one platform only.
- (c) Adopt it behind an annotation — a `/// sourcery:` verb that keeps the setter. It adds a record
  to `AnnotationRegistry.swift` and a verb to every rendered table, for a migration aid D6 already
  ruled against for names.

**D19 — when the twin table is corrected.**

**Ruled (a) — §12.8.**

- **(a) In this branch, before the tag (recommended).** The rows describe a processor that has
  already shipped its P1 to P3, and `CHANGELOG.md`'s entry points a reader at
  `references/generated-api.md` for the Kotlin map. If D18 (a) is taken, the transitional row their
  §12.3 item 1 names is never needed: both changes land together.
- (b) In a follow-up file and a separate documentation push after the tag. It leaves the tag
  shipping a table that is wrong in three rows.

**D20 — wrapping a method's handler-supplied publisher.**

**Ruled (a) — §12.8.**

- **(a) Not in this release (recommended).** It is unruled on both sides, it changes what
  `<name>SubscribeCount` and `<name>OutputCount` mean for a handler-seeded method, and §2.7's
  refusal and P7's construct are what this release already asks a consumer to absorb. Record it as
  open here and in their §11.7.
- (b) Take it now, so `<name>OutputCount` means "values delivered" for every member on both
  platforms. One `Deferred` around the handler's publisher in `MockMethod`'s branch, a behaviour
  check that a seeded method stream moves `SubscribeCount`, and a snapshot re-record.

**D21 — the overload tie-break (§12.5).**

**Ruled (a) — §12.8.**

- **(a) Add the fixture, then decide (recommended).** Two overloads with equal parameter counts
  where one has no argument label — `func send(_ value: String)` and `func send(to target: String)`
  — put the rule in `Snapshots/Mocks.generated.swift`, where the Kotlin side can read what this one
  produces. One fixture protocol, and it is what a comparison needs before either side changes.
- (b) Make the two rules one rule now, in both repositories, with no fixture on either side.
- (c) Record it as a known divergence in both twin tables and leave it. A protocol that hits it gets
  different member names on the two platforms, and nothing says so.

### 12.7 Phasing, if these are taken

**P12 — the get-only witness (D18).** `MockVar.swift:178` and `:195`; the three assignments and the
one assertion in `Tests/Checks/Behaviour/Main.swift`; `references/generated-api.md:131-132` and
`CONTRIBUTING.md:242-243` restated; `CHANGELOG.md` gains it as a second source break, with `_<var>`
as the one-line fix and the 12 measured sites in the consumer. Gates: `run-checks.sh` with the
snapshot re-recorded after the diff is read, both language modes, and the example lane.

**P13 — the twin table (D19).** `references/generated-api.md:226-245` takes the rows their §12.3
item 1 gives. No template change, so no snapshot moves. Gate: `run-skill-checks.sh` for the line
budget. The table is in a reference and not in the body, so the skill's token figure does not move.

**P14 — the overload tie-break fixture (D21 (a)).** One protocol in
`Tests/Checks/Fixtures/Naming.swift` and a re-record. Independent of the tag.

P12 and P13 land before the tag, and closing §9's P9 amendment is what they are for. P14 and D20 do
not block it.

### 12.8 Ruled

Ruled 2026-09-12: **D18 (a), D19 (a), D20 (a), D21 (a)** — each section's recommendation, so nothing
in §12.6 is superseded. What that settles:

- **D18 (a).** A `{ get }` requirement's witness becomes get-only, and `mock._<var> = value` is the
  one way a test seeds it — the same expression `kotlin-ksp-mocks` writes. It lands in this release,
  beside §2.1's renames.
- **D19 (a).** The twin table is corrected in this branch, before the tag. D18 (a) landing with it
  means the transitional row their §12.3 item 1 describes is never written.
- **D20 (a).** A method's handler-supplied publisher is not wrapped in this release. It stays open
  here and in their §11.7, and `<name>OutputCount` keeps the two meanings §12.2 item 3 names.
- **D21 (a).** The overload tie-break gets a fixture, so the name this generator produces is in the
  snapshot for the Kotlin side to read. Nothing about the rule changes yet.

P12, P13 and P14 are §12.7 as written. P12 and P13 close §9's P9 amendment; P14 does not block the
tag and lands with them because it is one fixture and a re-record.

---

## 13. What landed: P12, P13 and P14

### P12 — the get-only witness (D18 (a))

`MockVar.swift:178` is now `let hasSetter = !hasEffects && variable.isMutable`; the `<var>SetCount`
guard at `:195` reduces to `hasSetter`; the `if variable.isMutable` guard inside the setter body is
gone, because only a `{ get set }` requirement reaches a setter at all. The comment at `:167-177`
that recorded why P5 kept the witness settable is replaced by the rule it retires.

The emitted-rule table in §9's P5 entry takes one new value: `{ get }` gives a witness with `get`
only, and `<var>SetCount` is still not emitted. Every other row stands — `const` and `handler` were
get-only already, and an effectful requirement has no setter to lose.

| measured | value |
| --- | --- |
| snapshot | 92 lines added, 207 removed; 23 witnesses become a bare computed body, no member name moved |
| `modaal-firebase-wrappers`, regenerated from this tree | 3148 → **2803 lines**; 73 → **4** `set` blocks, the 69 §12.3 predicted |
| assignment sites in this repository | **5**, each now `_<var>` |

**§12.3 measured three of those five, and it was reading one file.** The other two are outside
`Tests/Checks/Behaviour/Main.swift`: `sut.profileID` in the example project's
`SwiftSourceryTemplatesMocksSpec.swift`, and `mock.profileID` in
`Tests/Checks/PluginFixture/Tests/AppTests/AppTests.swift`. Both were found by a lane rather than by
the grep, which is what the lanes are for; the consumer figure of 12 is from a grep over the same
kind of tree and carries the same risk of missing one.

`Main.swift:46` asserted `"a read-only requirement is settable on the mock"`. It now reads
`"a read-only requirement is seeded through its store"` and seeds `_recordPermission`.

**Documents.** `CHANGELOG.md` states it as the second source break in this release, with `_<var>` as
the fix at each site, the new 2803 total and two measured rows; `Adopting` gains a fourth step.
`CONTRIBUTING.md` §"Design rules already decided", `README.md`'s member table, `SKILL.md`'s member
table and `references/generated-api.md` each restate the rule.
`references/troubleshooting.md` gains `## cannot assign to property: 'x' is a get-only property`.

**Two lane defects found, neither caused by this phase and neither fixed.**

1. **`Tests/Examples/ExampleProjectSpm/test-ios.sh` exits 0 when the build fails.** Its log carried
   `Testing failed: Cannot assign to property: 'profileID' is a get-only property`,
   `Testing cancelled because the build failed.` and `** TEST FAILED **`, and the script still
   returned 0. A lane that cannot fail is a lane CI cannot gate on: read the log, not the status.
2. **`run-plugin-checks.sh` leaves its fixture scratch unusable after a failed run.** The next
   invocation fails with `couldn't build … because of missing inputs` naming the two generated
   files. `rm -rf .build/plugin-checks` and re-running is green. This is the second thing that
   directory does to a second run — §11 records the bundle-route warm-scratch defect.

### P13 — the twin table (D19 (a))

`references/generated-api.md`'s Swift → Kotlin table now says what item 1 of their §12.3 gives:
`<prop>GetCount` and `<prop>GetHandler` on **every** property there rather than on a `Flow` property
only; `<prop>SetCount` on a `var` requirement; `_<var>` → `_<prop>`, named as the only way to seed a
read-only requirement on either side; the six stream counters on a `Flow`-returning function or a
read-only `Flow` property; and `<name>Subject` against `<fn>Channel` with what separates them,
broadcast against single-consumer.

Two rows left "Members with no counterpart there" because they now have one. One row joined it: a
method whose handler supplies the publisher counts nothing here and is wrapped there, which is the
divergence D20 (a) leaves for a later release.

The transitional row their §12.3 item 1 describes — a settable witness for a `{ get }` requirement —
was never written, because P12 landed in the same branch.

No template change, so no snapshot moved. The file is back at 249 lines against SC5's 250, paid for
by dropping a sentence P12 had duplicated into the table, and it carries no version literal (SC9).

### P14 — the overload tie-break in the snapshot (D21 (a))

`NamingUnlabelledOverload` declares `send(_ value: String)` and `send(to target: String)` — the same
parameter count, one of them unlabelled, which is the input `areInAscendingOrder` decides and no
fixture in either repository had. The snapshot shows `send(_:)` keeping `send*` and `send(to:)`
taking `sendTo*`, with P10's comment above the second. 47 added lines, nothing else moved.
`Tests/Checks/README.md` gains the row.

### The record 004 owes (item 4 of their §12.3)

It is written here rather than in a follow-up file, because 004 is still being worked on and this
repository's rule is that a spec in flight takes new sections.

- **§8's closing paragraph** reads "Until it lands, its stored-property branch emits `SetCount`
  alone (`MockRenderer.kt:127-140`)". That is superseded: `kotlin-ksp-mocks`' P1 to P3 landed
  `<prop>GetCount`, `<prop>GetHandler`, `<prop>SetCount` and `_<prop>` on every property, and the
  six stream counters. §2.5 is adopted there, by its own D2, with `override val` where this side had
  `var` until D18.
- **P8's row** for `kotlin-ksp-mocks/skills/kotlin-ksp-mocks/references/generated-api.md` — and the
  "Not done here, and why" paragraph under P8 — describe the two tables as out of step until a
  follow-up lands in that repository. Half of that is now closed from this side: P13 corrected this
  repository's table. The other half is their §12.2, which is their work.

### What §9's P9 amendment still gates on

P12 and P13 are this repository's half. The tag also waits on `kotlin-ksp-mocks`' §12.2 — its D16
(a) file header and per-member comment, and its D17 (a) `find` in `SKILL.md` — because a published
version there is immutable, so both land before its 0.3.0 rather than after. Nothing in this
repository blocks on them; the amendment's wording is "re-align with the kotlin-ksp repo", and the
re-alignment is one ruling set applied on both sides.

Open after this branch, and neither is a gate: **D20 (a)**, wrapping a method's handler-supplied
publisher, recorded in their §11.7 as well; and their **D18 (c)**, which leaves a Kotlin interface
declaring a keyword-named requirement generating a file that fails its consumer's compile with no
diagnostic naming the requirement. §2.1's backtick rule here is unaffected.

### Lanes

`run-checks.sh` (snapshot re-recorded twice, after each diff was read), `run-skill-checks.sh`,
`run-annotation-checks.sh`, `run-cli-checks.sh`, `run-plugin-checks.sh` (cold, after clearing its
scratch) and `Tests/Examples/ExampleProjectSpm/test-ios.sh` at 20 tests, 0 failures — its log read
rather than its exit status. `run-xcode-checks.sh` was not run. The skill body measures ~4.9k tokens
on invoke at 208 lines, unchanged by P12's one-row edit, against 002 §3.1's 5,000-token floor.
