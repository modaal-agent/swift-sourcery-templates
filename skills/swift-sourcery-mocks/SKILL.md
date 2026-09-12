---
name: swift-sourcery-mocks
description: Generate Swift protocol mocks, type erasures and dependency-forwarding Components with the swift-sourcery-templates Sourcery templates. Use when asked to generate mocks for a Swift protocol, add a test double, set up Sourcery in a Swift package or an Xcode project, write a ProtocolMock or CreateMock annotation, generate a type erasure or a DuetComponent, commit pre-generated mocks so consumers need no Sourcery, or diagnose "does not conform to protocol" on a generated mock, a missing <method>Args, or a test that hangs waiting on a mock's publisher. Covers two lanes — the build-tool plugin that generates during the build, and the mock-templates CLI that writes generated files into the repository under a fingerprint CI can validate.
license: Apache-2.0
metadata:
  repository: https://github.com/modaal-agent/swift-sourcery-templates
---

# Swift mock generation with swift-sourcery-templates

Three templates — `Mocks`, `TypeErase`, `Component` — each selected by an annotation on a protocol.

## Pick the lane first

| what the repository is | lane |
| --- | --- |
| a SwiftPM package whose mocks compile into a test target of the same package | the build-tool plugin |
| an Xcode project with no `Package.swift` | the same plugin, through `XcodeBuildToolPlugin`; `${SOURCERY_SOURCES}` reaches the target's own input-file directories and no further, so name the others under `${SOURCERY_PROJECT}` |
| mocks committed, so a consumer or a cold CI job runs no generator | `mock-templates generate`, with `mock-templates validate` as the CI gate |
| a library shipping mocks downstream | `mock-templates generate`, committed. Generated mocks are `internal`, so the consumer writes `@testable import` |

One lane per target: a package generating at build time commits no generated file; one that commits
them does not run the plugin.

## Annotate the protocol

`/// sourcery: ProtocolMock` above `protocol DataService { … }` is the whole of it. Several
annotations on one declaration are comma-separated — `/// sourcery: ProtocolMock, DuetComponent` —
and a value is written with `=`: `/// sourcery: subject = "CurrentValue"`. **A protocol you do not
own** is annotated from an empty `extension ExternalProtocol {}`, in a directory the config scans.

<!-- annotations:start -->
<!-- Rendered from templates/Annotations/AnnotationRegistry.swift by Scripts/render-annotations.sh. Do not edit inside this block. -->

Annotation names are matched exactly, including case.

| Annotation | Target | Effect |
|------------|--------|--------|
| `ProtocolMock` | Protocol / extension | Generate the mock class |
| `ObjcProtocolMock` | Protocol / extension | Generate the mock class with an `NSObject` superclass. A protocol refining `NSObjectProtocol` gets one without the annotation |
| `TypeErasure` | Protocol | Generate the type-erasing wrapper |
| `DuetComponent` | Protocol | Generate the forwarding Component class |
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

`CreateMock`, `ObjcProtocol` and `TypeErase` still select the same templates, but write the table's
names in new code: a later release stops accepting them.
[references/writing-testable-protocols.md](references/writing-testable-protocols.md) has what to
annotate, the shapes that generate well, and the isolation a mock restates.

## The plugin lane

1. Add the package and the plugin to `Package.swift`, resolving `<newest tag>` with
   `git ls-remote --tags https://github.com/modaal-agent/swift-sourcery-templates.git | tail -1`:

```swift
.package(url: "https://github.com/modaal-agent/swift-sourcery-templates.git", from: "<newest tag>"),
// and on every target that generates:
plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
```

2. Put a `*.sourcery*.yml` config in the source directory of every generating target — three lines:

```yml
templates:
  - Mocks
```

The plugin fills in the sources, the output directory the build collects from, and — for a test
target with exactly one direct dependency on a module of the same package — `args.testable`.

3. Build. The plugin logs every variable it exported, every default it supplied and every template
   it resolved.

**Reading beyond the target.** `${SOURCERY_SOURCES}` is the target's own sources plus the recursive
closure of its dependencies, so a mock carries requirements inherited further down the graph. Write
it under `sources:`, with any further directory beside it, such as
`${SOURCERY_TARGET_MyModuleTests}/SourceryAnnotations`. A list without it is scanned as written.

**Where it writes.** Omit `output:`, or write `${SOURCERY_OUTPUT_DIR}`. Any other directory fails the
build: a prebuild command's outputs are collected only from the one it declared.

**Finding what it wrote.** The generated file is a build product, not a file in the repository:
`find .build -path '*/SourcerySwiftCodegenPlugin/.generatedFiles/*' -name '*.generated.swift'`. An
Xcode project's build root is derived data rather than `.build`.

**Naming a template.** A `templates:` entry may be the bare name of a shipped template — `Mocks`,
`TypeErase`, `Component` — one `<Template>.generated.swift` per entry. The rest of the config is
carried through unread, and every path it writes must be absolute: the plugin runs a copy from its
own work directory.
[references/spm-plugin.md](references/spm-plugin.md) has the exported variables, the resolution order
for a template name, Xcode, and how to find the output there.

## The CLI lane

`mock-templates generate` writes the output under a fingerprint block — the bundle tag, the config,
the path and SHA-256 of every scanned source, and the SHA-256 of the body. `validate` re-hashes it
without running the generator, so a cold CI job proves the files current in seconds. The CLI ships in
the release artifact bundle with the engine and `templates/`, all at one tag;
[references/cli-lane.md](references/cli-lane.md) has the download, every flag and `imprint`.

Generate one output file per module, in a script the repository commits. `generate` takes
`--sourcery` and `--templates` from the unpacked bundle, one or more `--sources`, `--args`,
`--bundle-version`, `--root "$(pwd)"` and `--output`; `cli-lane.md` above has the loop to copy.

Gate it in CI with `mock-templates validate`, which needs no engine download: `--file` the generated
file, `--root "$(pwd)"`, and the same `--sources`, `--template` and `--args`. It fails on an input
that changed, went missing or was added, on a hand-edited body, and — given `--template` and
`--args` — on a config that no longer matches.

## What the generated mock gives a test

```swift
let service = DataServiceMock()
sut.load(id: "m1")
XCTAssertEqual(service.fetchDataCallCount, 1)
XCTAssertEqual(service.fetchDataArgs, ["m1"])
service.fetchDataHandler = { id, completion in completion("payload", nil) }
```

**A mock member is the declared name plus a suffix.** The name is taken verbatim — no case change,
no underscore removal — with backticks dropped: `func perform1_0()` gives `perform1_0CallCount`,
``func `do`()`` gives `doCallCount`, `var setting4_2: Int` gives `setting4_2GetCount`.

**Overloads.** The one with the fewest parameters keeps the plain name; each other appends the
capitalized argument label of every parameter, or the parameter name where there is no label —
`func end(atDocument document:)` gives `endAtDocument`. Overloads differing only in return type get
a suffix from that type, and anything still colliding fails generation naming both members.

**The generated file names the ones it did not derive.** It states the rule at the top and under
every `// MARK:`, and a member whose prefix is not its declared name carries ``// `end(at:)` members
are named `endAt*` — overload of `end`, argument labels appended`` above the witness and in its
class's index. Search for either spelling.

| member | on | what it holds |
| --- | --- | --- |
| `<method>CallCount` | method | how many times the requirement was called |
| `<method>Args` | method | what each call was passed, in order: `[T]` for one recordable parameter, `[(first: A, second: B)]` for more, labelled with the parameter names |
| `<method>Handler` | method | the closure the test sets to decide the return value and the side effects; `async` and `throws` carry through to it |
| `<var>GetCount` / `<var>GetHandler` | property | every property requirement counts its reads; the handler supplies the value |
| `<var>SetCount` / `_<var>` | property | writes to a `{ get set }` requirement, and the store — `_<var>` reads and seeds without moving a counter, and is the only way to seed a `{ get }` one |
| `<name>Subject` | both | the subject behind an `AnyPublisher` or RxSwift member, which the test drives with `send` |
| `<name>SubscribeCount` / `<name>SubscribeCancelCount` / `<name>CompletionCount` | both | an `AnyPublisher` member: the code under test subscribed, cancelled, saw the stream end |
| `<name>OutputCount` / `<name>Outputs` / `<name>OutputHandler` | both | an `AnyPublisher` member: what it **delivered** — counted, recorded, handed to the handler |
| `<name>EventCallCount` / `<name>Events` / `<name>EventHandler` | both | an `AnyObserver` member: the events pushed **in**, the same three ways |
| `<method>CancelCallCount` / `<method>CancelHandler`, `<method>DisposeCallCount` / `<method>DisposeHandler` | method | the returned `AnyCancellable` was cancelled, or the returned RxSwift `Disposable` disposed |

A returned token's suffix is the call it exposes: `cancel()`, `dispose()`. Closure parameters, a
generic method's parameters and anything `skipArgumentRecording` covers are not recorded — assert
through the handler; that annotation drops `<name>Outputs` and `<name>Events` too.

**A property declared `{ get async }`, `{ get throws }` or `{ get async throws }`** generates the
accessor it declares, and `<var>GetHandler` carries the same effects. Swift has no effectful setter,
so it has no `<var>SetCount`; seed `_<var>`. A member with no handler set returns a default — `nil`
for an `Optional`, a usable empty value for a known type. Mock classes are `final`: set a handler
rather than subclassing one.

**Drive a publisher member through its subject:**

```swift
let token = repo.ownMemories.sink { received.append($0) }  // subscribe first
repo.ownMemoriesSubject.send([drop])                       // then send
```

The default `PassthroughSubject` delivers nothing to a subscriber that arrives after the value was
sent, so subscribe first or annotate the member `subject = "CurrentValue"` to replay one; a test
collecting to the end also has to `send(completion: .finished)`.

[references/generated-api.md](references/generated-api.md) has the emitted Swift for each shape and
the Kotlin member map; [references/stream-members.md](references/stream-members.md) the publisher and
RxSwift shapes, their counters, and when each handler is read.

## When it goes wrong

- `type 'XMock' does not conform to protocol 'Y'` — the refined protocol was not parsed. Plugin:
  `- ${SOURCERY_SOURCES}` in `sources:`. CLI: the other module's directory as another `--sources`.
- the target compiles and a generated type is missing — `output:` named a directory the build does
  not collect from. Omit it, or write `${SOURCERY_OUTPUT_DIR}`.
- `'createmock' on 'Foo' is not 'ProtocolMock'` — spelling is matched including case.
- a protocol generates no mock and nothing is reported — no selector on the declaration, or the file
  is under no scanned source root.
- the generator will not run, unidentified developer — the engine binary is quarantined:
  `xattr -dr com.apple.quarantine <bundle>/sourcery/bin/sourcery`.
- a Combine test hangs, or a continuation resumes twice — a `PassthroughSubject`-backed member does
  not replay. Subscribe before sending, or annotate `subject = "CurrentValue"`.
- `<method>Args` does not exist — every parameter is a closure, the method is generic, or
  `skipArgumentRecording` covers it. Assert through `<method>Handler`.
- a Component fails generation naming a member — `static`, `init`, `subscript` and associated types
  cannot be forwarded. Hand-write it, or annotate `DuetComponent, owns` and write the subclass.
- the Swift 6 test body is rejected — calling a `nonisolated async` member of a non-Sendable mock
  from the main actor crosses isolation. Make the test body non-isolated.

[references/troubleshooting.md](references/troubleshooting.md) has each in full, with the diagnostic
text.
