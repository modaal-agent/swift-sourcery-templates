---
name: swift-sourcery-mocks
description: Generate Swift protocol mocks, type erasures and dependency-forwarding Components with the swift-sourcery-templates Sourcery templates. Use when asked to generate mocks for a Swift protocol, add a test double, set up Sourcery in a Swift package or an Xcode project, write a ProtocolMock or CreateMock annotation, generate a type erasure or a DuetComponent, commit pre-generated mocks so consumers need no Sourcery, or diagnose "does not conform to protocol" on a generated mock, a missing <method>Args, or a test that hangs waiting on a mock's publisher. Covers two lanes — the build-tool plugin that generates during the build, and the mock-templates CLI that writes generated files into the repository under a fingerprint CI can validate.
license: Apache-2.0
metadata:
  repository: https://github.com/modaal-agent/swift-sourcery-templates
---

# Swift mock generation with swift-sourcery-templates

Three templates, each selected by an annotation on a protocol: `Mocks` writes the mock class,
`TypeErase` the type-erasing wrapper, `Component` the forwarding class of a dependency-injection
tree.

## Pick the lane first

| what the repository is | lane |
| --- | --- |
| a SwiftPM package whose mocks compile into a test target of that same package | the build-tool plugin |
| an Xcode project with no `Package.swift` | the same plugin, through `XcodeBuildToolPlugin`. `${SOURCERY_SOURCES}` reaches the target's own input-file directories and no further, so name every other directory in `sources:` under `${SOURCERY_PROJECT}` |
| mocks committed to the repository, so a consumer or a cold CI job runs no generator | `mock-templates generate`, with `mock-templates validate` as the CI gate |
| a library shipping mocks to downstream packages | `mock-templates generate`, committed. Generated mocks are `internal`, so the consumer writes `@testable import` |

One lane per target: a package that generates at build time commits no generated file; a repository
that commits them does not run the plugin.

## Annotate the protocol

```swift
/// sourcery: ProtocolMock
protocol DataService {
    func fetchData(id: String, completion: @escaping (String?, Error?) -> Void)
}
```

Several annotations on one declaration are comma-separated — `/// sourcery: ProtocolMock,
DuetComponent` — and a value is written with `=`, as in `/// sourcery: subject = "CurrentValue"`.

**A protocol you do not own** is annotated through an empty extension, in a directory of its own
that the generation config also scans:

```swift
// SourceryAnnotations/ExternalFramework+Mocks.swift
import ExternalFramework

/// sourcery: ProtocolMock
extension ExternalProtocol {}
```

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

The legacy spellings `CreateMock`, `ObjcProtocol` and `TypeErase` still select the same templates;
write the table's names in new code, because a release after the current one stops accepting them
and generation then fails naming the replacement.
[references/writing-testable-protocols.md](references/writing-testable-protocols.md) has what to
annotate, the shapes that generate well, and the isolation a mock restates.

## The plugin lane

1. Add the package and the plugin to `Package.swift`, resolving `<newest tag>` with
   `git ls-remote --tags https://github.com/modaal-agent/swift-sourcery-templates.git | tail -1`:

```swift
dependencies: [
    .package(url: "https://github.com/modaal-agent/swift-sourcery-templates.git", from: "<newest tag>"),
],
targets: [
    .testTarget(
        name: "MyModuleTests",
        dependencies: [.target(name: "MyModule")],
        plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
]
```

2. Put a `*.sourcery*.yml` config in the source directory of every target that generates — three
   lines is enough:

```yml
# Sources/MyModuleTests/.Sourcery.Mocks.yml
templates:
  - Mocks
```

The plugin fills in the sources, the output directory the build collects from, and — for a test
target with exactly one direct dependency on a module of the same package — `args.testable`.

3. Build. The plugin logs every exported variable, every default it supplied and every template
   name it resolved.

**Reading beyond the target.** `${SOURCERY_SOURCES}` expands to the target's own sources plus the
recursive closure of its dependencies, one directory per module, so a mock carries requirements its
protocol inherits further down the graph:

```yml
templates:
  - Mocks
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_TARGET_MyModuleTests}/SourceryAnnotations
```

A `sources:` list without the placeholder is scanned exactly as written.

**Where it writes.** Omit `output:`, or write `output: ${SOURCERY_OUTPUT_DIR}`. Any other directory
fails the build: a prebuild command's outputs are collected only from the directory it declared.

**Naming a template.** A `templates:` entry may be the bare name of a shipped template — `Mocks`,
`TypeErase`, `Component` — and Sourcery writes one `<Template>.generated.swift` per entry.

Everything else is carried through unread, and every path the config writes must be absolute: the
plugin runs a copy of it from its own work directory.
[references/spm-plugin.md](references/spm-plugin.md) has the exported variables, the resolution order
for a template name, and Xcode.

## The CLI lane

`mock-templates generate` writes the output under a fingerprint block naming the bundle tag, the
config, the path and SHA-256 of every scanned source, and the SHA-256 of the generated body.
`validate` re-hashes all of it without running the generator, so a cold CI job proves the committed
files current in seconds.

`mock-templates` ships in the release artifact bundle with the generator engine and `templates/`,
all at one tag. [references/cli-lane.md](references/cli-lane.md) has the download, every flag and
`imprint`.

Generate one output file per module, in a script the repository commits:

```bash
VERSION=<newest tag>
BUNDLE="swift-sourcery-templates-$VERSION.artifactbundle"
"$BUNDLE/mock-templates/bin/mock-templates" generate \
  --sourcery "$BUNDLE/sourcery/bin/sourcery" \
  --templates "$BUNDLE/templates/Mocks.swifttemplate" \
  --sources Sources/MyModule \
  --sources SourceryAnnotations \
  --args "import=Foundation,testable=MyModule" \
  --bundle-version "$VERSION" \
  --root "$(pwd)" \
  --output Tests/MyModuleTests/Generated/MyModuleMocks.swift
```

Gate it in CI with the CLI alone, which needs no engine download:

```bash
mock-templates validate \
  --file Tests/MyModuleTests/Generated/MyModuleMocks.swift \
  --root "$(pwd)" \
  --sources Sources/MyModule \
  --sources SourceryAnnotations \
  --template Mocks.swifttemplate \
  --args "import=Foundation,testable=MyModule"
```

`validate` fails on an input that changed, went missing or was added, on a hand-edited body, and —
with `--template` and `--args` — on a config that no longer matches the one that generated the file.

## What the generated mock gives a test

```swift
let service = DataServiceMock()
sut.load(id: "m1")

XCTAssertEqual(service.fetchDataCallCount, 1)
XCTAssertEqual(service.fetchDataArgs, ["m1"])
service.fetchDataHandler = { id, completion in completion("payload", nil) }
```

| member | what it holds |
| --- | --- |
| `<method>CallCount` | how many times the requirement was called |
| `<method>Args` | what each call was passed, in order. One recordable parameter gives `[T]`; two or more give `[(first: A, second: B)]`, labelled with the parameter names |
| `<method>Handler` | the closure the test sets to control the return value and the side effects. `async` and `throws` are carried through to it |
| `<var>GetCount` / `<var>GetHandler` / `<var>SetCount` | the same three for a property requirement |
| `<method>Subject` / `<var>Subject` | the subject backing an `AnyPublisher` or an RxSwift member, which the test drives with `send` |
| `<method>CancelCallCount` | for a method returning `AnyCancellable` or a `Disposable`: how many times the returned token was cancelled |

Closure parameters, a generic method's parameters and anything annotated `skipArgumentRecording` are
not recorded — assert through the handler.

Return values default without a handler: `Optional` gives `nil`, `Void` gives nothing, known types
give a usable empty value. Mock classes are `final` — set a handler rather than subclassing one.

The generated file compiles at zero diagnostics under `-swift-version 5
-strict-concurrency=complete` and under `-swift-version 6`: the protocol's global actor lands on the
mock class, `nonisolated` is carried through, and a `Sendable` protocol gets `@unchecked Sendable`.

The emitted Swift for each shape, and the member map to the Kotlin twin, is
[references/generated-api.md](references/generated-api.md).

## Publishers are subject-backed

An `AnyPublisher` requirement, on a property or a method, is generated with a subject the test sends
into, named `<var>Subject` or `<method>Subject`:

```swift
let repo = MemoryRepositoryMock()
var received: [[MemoryDrop]] = []
let token = repo.ownMemories.sink { received.append($0) }   // subscribe first
repo.ownMemoriesSubject.send([drop])                        // then send
```

The default is a `PassthroughSubject`, which delivers nothing to a subscriber that arrives after the
value was sent, so a test that seeds in `setUp` and subscribes in the body waits. To make the member
replay, annotate it `subject = "CurrentValue"` — a `CurrentValueSubject` seeded with the `Output`'s
default value — or return a publisher of your own from `<var>GetHandler`. A test that collects to the
end also has to `send(completion: .finished)`.

## When it goes wrong

| symptom | cause | action |
| --- | --- | --- |
| `type 'XMock' does not conform to protocol 'Y'` | the refined protocol was not among the parsed sources | plugin: put `- ${SOURCERY_SOURCES}` in `sources:`. CLI: add the other module's directory as another `--sources` |
| the target compiles and a generated type is missing | `output:` named a directory the build does not collect from | omit `output:`, or write `${SOURCERY_OUTPUT_DIR}` |
| `'createmock' on 'Foo' is not 'ProtocolMock'` | the spelling differs from the registry's only in case | spell it exactly — matching includes case |
| a protocol generates no mock and nothing is reported | the declaration carries no selector, or the file is not under any scanned source root | annotate it, or add its directory to the sources |
| the generator will not run — unidentified developer | the downloaded engine binary is quarantined | `xattr -dr com.apple.quarantine <artifact bundle>/sourcery/bin/sourcery` |
| a Combine test hangs, or a continuation resumes twice | a `PassthroughSubject`-backed `AnyPublisher` member does not replay | subscribe before sending, or annotate `subject = "CurrentValue"` |
| `<method>Args` does not exist | every parameter is a closure, the method is generic, or `skipArgumentRecording` is on the method or its protocol | assert through `<method>Handler` |
| a Component fails generation naming a member | `static`, `init` and `subscript` requirements and associated types cannot be forwarded | hand-write that member, or annotate `DuetComponent, owns` and write the subclass |
| the Swift 6 test body is rejected | calling a `nonisolated async` member of a non-Sendable mock from the main actor crosses an isolation boundary | make the test body non-isolated |

[references/troubleshooting.md](references/troubleshooting.md) has each of these in full, with the
diagnostic text to match against.
