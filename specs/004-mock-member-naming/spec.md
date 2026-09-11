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
