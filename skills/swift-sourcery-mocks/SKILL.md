---
name: swift-sourcery-mocks
description: Generate Swift protocol mocks, type erasures and dependency-forwarding Components with the swift-sourcery-templates Sourcery templates. Use when asked to generate mocks for a Swift protocol, add a test double, set up Sourcery in a Swift package or an Xcode project, write a ProtocolMock or CreateMock annotation, generate a type erasure or a DuetComponent, commit pre-generated mocks so consumers need no Sourcery, or diagnose "does not conform to protocol" on a generated mock, a missing <method>Args, or a test that hangs waiting on a mock's publisher. Covers two lanes — the build-tool plugin that generates during the build, and the mock-templates CLI that writes generated files into the repository under a fingerprint CI can validate.
license: Apache-2.0
metadata:
  repository: https://github.com/modaal-agent/swift-sourcery-templates
---

# Swift mock generation with swift-sourcery-templates

Three templates, each selected by an annotation on a protocol: `Mocks` writes the mock class,
`TypeErase` writes the type-erasing wrapper, `Component` writes the forwarding class of a
dependency-injection tree.

## Pick the lane first

| what the repository is | lane |
| --- | --- |
| a SwiftPM package whose mocks compile into a test target of that same package | the build-tool plugin |
| an Xcode project with no `Package.swift` | the same plugin, through `XcodeBuildToolPlugin`. `${SOURCERY_SOURCES}` reaches the target's own input-file directories and no further, so name every other directory in `sources:` as an absolute path under `${SOURCERY_PROJECT}` |
| mocks committed to the repository, so a consumer or a cold CI job runs no generator | `mock-templates generate`, with `mock-templates validate` as the CI gate |
| a library shipping mocks as a product to downstream packages | `mock-templates generate`, committed. Generated mocks are `internal`, so the consumer writes `@testable import` |

A package that generates at build time does not commit generated files; a repository that commits
them does not run the plugin. Do not set up both for one target.

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
| `skipArgumentRecording` | Protocol / method | Do not generate `<method>Args`; call counting and the handler are unaffected |
| `owns` | Protocol | Emit `<X>ComponentBase` (non-final) for a hand-written subclass that holds what the level owns |
| `componentName = "Foo"` | Protocol | Name the emitted Component `Foo` instead of deriving it from the protocol |
| `componentAccess = "public"` | Protocol | Emit a `public` Component; the default is internal |
<!-- annotations:end -->

The legacy spellings `CreateMock`, `ObjcProtocol` and `TypeErase` still select the same templates.
Write the names in the table above in new code; a release after the current one stops accepting the
legacy three, and generation then fails naming the replacement.

## The plugin lane

1. Add the package and the plugin to `Package.swift`. Resolve the newest tag first —
   `git ls-remote --tags https://github.com/modaal-agent/swift-sourcery-templates.git | tail -1` —
   and write it where `<newest tag>` stands:

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

2. Put a `*.sourcery*.yml` config in the source directory of every target that generates. The
   smallest config that works is three lines:

```yml
# Sources/MyModuleTests/.Sourcery.Mocks.yml
templates:
  - Mocks
```

The plugin fills in the sources, the output directory the build collects from, and — for a test
target with exactly one direct dependency on a module of the same package — `args.testable`.

3. Build. The plugin writes every exported variable, every default it supplied and every template
   name it resolved to the build log.

**Reading beyond the target.** `${SOURCERY_SOURCES}` expands to the target's own sources plus the
recursive closure of its dependencies, one directory per module, which is what lets a mock carry the
requirements its protocol inherits from a module further down the graph:

```yml
templates:
  - Mocks
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_TARGET_MyModuleTests}/SourceryAnnotations
```

A `sources:` list without the placeholder is scanned exactly as written and the plugin appends
nothing to it.

**Where it writes.** Omit `output:`, or write `output: ${SOURCERY_OUTPUT_DIR}`. Any other directory
fails the build naming both paths, because a prebuild command's outputs are collected only from the
directory it declared.

**Naming a template.** A `templates:` entry may be the bare name of a shipped template — `Mocks`,
`TypeErase`, `Component`. A file of that exact name beside the config wins over the shipped one. One
config may name several templates, and Sourcery writes one `<Template>.generated.swift` per entry.

Everything else in the config is carried through unread, and every path it writes must be absolute:
the plugin runs a copy of the config from its own work directory. The full reference — exported
variables, template-name resolution, Xcode — is [references/spm-plugin.md](references/spm-plugin.md).

## The CLI lane

`mock-templates` runs the generator and writes the output under a fingerprint block naming the
template bundle tag, the config, the path and SHA-256 of every scanned source, and the SHA-256 of
the generated body. `validate` re-hashes all of it without running the generator, so a cold CI job
proves the committed files current in seconds.

Get the binaries from the release artifact bundle, which carries the generator engine, `templates/`
and the CLI at one tag:

```bash
VERSION=<newest tag>
BASE=https://github.com/modaal-agent/swift-sourcery-templates/releases/download/$VERSION
curl -fsSLO "$BASE/swift-sourcery-templates-$VERSION.artifactbundle.zip"
curl -fsSLO "$BASE/swift-sourcery-templates-$VERSION.artifactbundle.zip.sha256"
shasum -a 256 -c "swift-sourcery-templates-$VERSION.artifactbundle.zip.sha256"
unzip -q "swift-sourcery-templates-$VERSION.artifactbundle.zip"
```

Generate one output file per module, in a script the repository commits:

```bash
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

Gate it in CI with the CLI alone — `mock-templates-<version>-macos.zip`, published beside the
bundle, needs no engine download:

```bash
mock-templates validate \
  --file Tests/MyModuleTests/Generated/MyModuleMocks.swift \
  --root "$(pwd)" \
  --sources Sources/MyModule \
  --sources SourceryAnnotations \
  --template Mocks.swifttemplate \
  --args "import=Foundation,testable=MyModule"
```

`validate` fails on a changed input, a missing input, a `.swift` file present under `--sources` and
absent from the block, a hand-edited body, and — with `--template` and `--args` — a config that no
longer matches the one that generated the file. Every flag and `imprint` are in
[references/cli-lane.md](references/cli-lane.md).

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

Closure parameters, the parameters of a generic method, and anything annotated
`skipArgumentRecording` are not recorded; assert on those through the handler.

Return values default without a handler: `Optional` gives `nil`, `Void` gives nothing, known types
give a usable empty value. Mock classes are `final` — set a handler rather than subclassing one.

The generated file compiles at zero diagnostics under `-swift-version 5
-strict-concurrency=complete` and under `-swift-version 6`: the protocol's global actor lands on the
mock class, `nonisolated` is carried through, and a `Sendable` protocol gets `@unchecked Sendable`.

The emitted Swift for each shape — the argument tuple, what an unset handler returns, the
initializer-seeded bag, the overload names — is
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
value was sent — a test that seeds in `setUp` and subscribes in the test body sees nothing and waits.
Two ways to make the member replay: annotate the requirement `subject = "CurrentValue"`, which backs
it with a `CurrentValueSubject` seeded with the `Output`'s default value, or return a publisher of
your own from `<var>GetHandler`. A test that collects to the end also has to finish the stream —
`send(completion: .finished)`.

## When it goes wrong

| symptom | cause | action |
| --- | --- | --- |
| `type 'XMock' does not conform to protocol 'Y'` | the refined protocol was not among the parsed sources | plugin: put `- ${SOURCERY_SOURCES}` in `sources:`. CLI: add the other module's directory as another `--sources` |
| the target compiles and a generated type is missing | `output:` named a directory the build does not collect from | omit `output:`, or write `${SOURCERY_OUTPUT_DIR}` |
| `'createmock' on 'Foo' is not 'ProtocolMock'` | a selector's spelling differs from the registry's only in case | spell it exactly: names are matched including case |
| a protocol generates no mock and nothing is reported | the declaration carries no selector, or the file is not under any scanned source root | annotate it, or add its directory to the sources |
| the generator will not run — unidentified developer | the downloaded engine binary is quarantined | `xattr -dr com.apple.quarantine <path to the resolved artifact bundle>/sourcery/bin/sourcery` |
| a Combine test hangs, or a continuation resumes twice | an `AnyPublisher` member is backed by a `PassthroughSubject`, which does not replay | send after subscribing, return a `CurrentValueSubject` from `<name>GetHandler`, or annotate `subject = "CurrentValue"` |
| `<method>Args` does not exist | every parameter is a closure, the method is generic, or `skipArgumentRecording` is on the method or its protocol | assert through `<method>Handler` |
| a Component fails generation naming a member | `static`, `init` and `subscript` requirements and associated types cannot be forwarded | hand-write that member, or annotate `DuetComponent, owns` and write the subclass |
| the Swift 6 test body is rejected | a mock of a non-isolated protocol is a non-Sendable class, and calling a `nonisolated async` member from the main actor crosses an isolation boundary | make the test body non-isolated |

Each of these in full, with the diagnostic text to match against, is in
[references/troubleshooting.md](references/troubleshooting.md).

## References

- [references/spm-plugin.md](references/spm-plugin.md) — the config reference, both plugin paths.
- [references/cli-lane.md](references/cli-lane.md) — every `mock-templates` flag and the bundle.
- [references/writing-testable-protocols.md](references/writing-testable-protocols.md) — what to
  annotate, and how to shape a protocol so its mock is usable.
- [references/troubleshooting.md](references/troubleshooting.md) — one section per symptom.
- [references/generated-api.md](references/generated-api.md) — the emitted Swift, shape by shape,
  and the member map to the Kotlin twin.
