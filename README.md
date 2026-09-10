# swift-sourcery-templates

[![CI](https://github.com/modaal-agent/swift-sourcery-templates/actions/workflows/ci.yml/badge.svg)](https://github.com/modaal-agent/swift-sourcery-templates/actions/workflows/ci.yml)

Advanced Protocol Mock, Type Erasure and dependency-forwarding Code-generation templates for Swift (using [Sourcery](https://github.com/krzysztofzablocki/Sourcery)).

Three templates:

1. **`Mocks.swifttemplate`** — generates protocol mock classes for [test doubles](https://martinfowler.com/bliki/TestDouble.html) with call counting, handler closures, and smart defaults
2. **`TypeErase.swifttemplate`** — generates [type erasure](https://www.bignerdranch.com/blog/breaking-down-type-erasure-in-swift/) wrappers
3. **`Component.swifttemplate`** — generates the forwarding class that satisfies a dependency-injection protocol, for trees where each level declares what it consumes. See [Components](#components)

The first two support protocols with associated types, generic functions with constraints, `@escaping` closure parameters,
and provide smart defaults for RxSwift and Combine types. Compatible with [RIBs](https://github.com/uber/RIBs) architecture patterns.

Generated mocks compile with **zero diagnostics** under `-strict-concurrency=complete` and in the
Swift 6 language mode: `async` and `nonisolated` are carried through to the mock, a protocol's
global actor is declared on the mock class, and a `Sendable` protocol gets an `@unchecked`
conformance. See [Concurrency](#concurrency).

## Generated Mock API

For a protocol method:

```swift
/// sourcery: ProtocolMock
protocol DataService {
    func fetchData(id: String, completion: @escaping (String?, Error?) -> Void)
}
```

The template generates:

```swift
final class DataServiceMock: DataService {
    func fetchData(id: String, completion: @escaping (String?, Error?) -> Void) {
        fetchDataCallCount += 1
        fetchDataArgs.append(id)
        if let __fetchDataHandler = self.fetchDataHandler {
            __fetchDataHandler(id, completion)
        }
    }
    var fetchDataCallCount: Int = 0
    var fetchDataArgs: [String] = []
    var fetchDataHandler: ((_ id: String, _ completion: @escaping (String?, Error?) -> Void) -> ())? = nil
}
```

**Key features:**
- **Call counting** — `methodCallCount` tracks invocation count
- **Argument recording** — `methodArgs` holds what each call was passed, in order. See [Recorded arguments](#recorded-arguments)
- **Handler closures** — `methodHandler` lets tests control behavior
- **`@escaping` / `@Sendable` preservation** — closure parameters retain both attributes in the method signature and the handler type, so handlers can capture, async-dispatch, and hand off closures that cross isolation boundaries
- **`async` / `throws` preservation** — an `async` requirement generates an `async` method with an `async` handler, so a spec can control *when* the call returns, not only what it returns
- **Smart defaults** — Optional returns `nil`, Void returns nothing, known types get sensible defaults, and RxSwift / Combine types get a subject the test drives
- **Overload disambiguation** — overloaded methods get distinct handler names automatically

## Recorded arguments

Every call appends what it was passed to `<method>Args`, so asserting on an argument needs no handler
and no side object:

```swift
let service = DataServiceMock()          // func fetchData(id: String, completion: …)
let registry = AppServicesRegisteringMock()   // func registerURLHandler(_ tag: String, priority: Int)

sut.load(id: "m1")

XCTAssertEqual(service.fetchDataArgs, ["m1"])                        // one parameter: its own type
XCTAssertEqual(registry.registerURLHandlerArgs.last?.priority, 3)    // two: a labelled tuple
service.fetchDataArgs = []                                           // clearing it is the reset
```

| the method's parameters | `<method>Args` |
| --- | --- |
| none | not generated |
| one recordable | `[T]` — Swift has no single-element labelled tuple to put it in |
| two or more recordable | `[(first: A, second: B)]`, labelled with the parameter names, one element per call |
| a mix of recordable and closure | the recordable ones only |
| `inout T` | `[T]` — the value the caller passed in; the handler still gets the reference |

Three things are deliberately not recorded:

- **Closure parameters.** A non-escaping closure cannot be stored at all, and storing an escaping one
  would keep the caller's captures alive for as long as the mock — which a leak or churn spec reads
  as a retain by the code under test. What a spec does with a closure is call it, and the handler
  hands it over.
- **Generic methods.** Their parameter types name the *method's* generic parameters; a stored
  property can only name the class's.
- **Anything annotated `skipArgumentRecording`** — on the method, or on the protocol for all of them.
  A recorded argument lives as long as the mock, so this is the opt-out for an argument whose
  deallocation a spec asserts. Call counting and the handler are unaffected.

## Concurrency

The generated file is held to zero diagnostics under `-swift-version 5 -strict-concurrency=complete`
and under `-swift-version 6` — see [`Tests/Checks/`](Tests/Checks).

| protocol declares | mock gets |
| --- | --- |
| `@MainActor` (or any attribute ending in `Actor`) | the same attribute on the class, so the conformance is isolated rather than inferred |
| `nonisolated func` / `nonisolated var` on an isolated protocol | `nonisolated` on the member and `nonisolated(unsafe)` on its call counter and handler — without both, the member cannot mutate its own bookkeeping |
| `func f() async throws -> T` | `func f() async throws -> T` with handler `((…) async throws -> (T))?`, awaited at the call |
| `: Sendable` | `final class …: P, @unchecked Sendable` — a test double holds mutable counters, so the conformance cannot be checked |
| `@Sendable` closure parameter | the attribute restated in the signature and the handler type, so the captured closure can be handed to `@Sendable`-constrained code |
| a global actor Sourcery cannot name from the attribute | declare it: `/// sourcery: globalActor = "MyIsolation"` |

Two deliberate non-goals:

- **Member-level global actors are not propagated.** A protocol that is not isolated but whose method
  is `@MainActor` produces a non-isolated mock method. That satisfies the requirement, and it keeps
  the mock callable from a non-isolated test body.
- **Mock classes are `final`.** Subclassing a generated mock is not supported; set a handler instead.

## Combine

An `AnyPublisher<Output, Failure>` requirement is backed by a subject the test drives:

```swift
/// sourcery: ProtocolMock
@MainActor
protocol UserRepositoryProtocol {
    var meStream: AnyPublisher<UserSummary?, Never> { get }
    func bootstrap(displayName: String?) -> AnyPublisher<Void, Error>
}
```

```swift
mock.meStreamSubject.send(UserSummary(uid: "u1", displayName: "Ada"))   // state, replayed
mock.bootstrapSubject.send(())                                          // event
```

The subject is a **`PassthroughSubject`**, for a variable and for a method alike — the same rule the
RxSwift members follow with `PublishSubject`. The double emits what the test sends it and nothing
else, so a subscriber that attaches after a send has missed it.

**A stream that replays is the test's to supply**, through the closure every publisher member already
has — `<name>GetHandler` on a variable, `<name>Handler` on a method:

```swift
let state = CurrentValueSubject<UserSummary?, Never>(me)
mock.meStreamGetHandler = { state.eraseToAnyPublisher() }   // now it replays
```

Seeding by default instead would make the double emit a value nobody wrote — `""`, `[:]`, `[]` — the
moment the code under test subscribes, and turn the test's own `send` into a *second* element; a
bridge awaiting the first value then resumes its continuation twice and traps. It is also
un-opt-out-able by construction, since assigning a `PassthroughSubject` to a
`CurrentValueSubject`-typed property does not compile.

`/// sourcery: subject = "CurrentValue"` states the seeded form at the declaration, for the member
where every test wants it; asking for it where `Output` has no default value is an error, not a
silent downgrade.

A method returning `AnyCancellable` gets a token whose `cancel()` is counted —
`<method>CancelCallCount` and `<method>CancelHandler` — mirroring the RxSwift `Disposable` case, so a
registration API's deregistration is observable without setting a handler.

## Components

In a dependency-injection tree where every level declares an `<X>Dependency` protocol naming exactly
what it consumes, the class that satisfies that protocol by forwarding to the parent is mechanical:
one `var m: T { dependency.m }` per requirement. `Component.swifttemplate` writes it.

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

The parent satisfies a child's Dependency with an empty extension when its own surface covers it
(`extension MainComponent: TimelineDependency {}`), so the tree is written once, in the protocols.

**A level that owns something** annotates `DuetComponent, owns`. A generated type cannot carry a
hand-written `lazy var`, so the emission becomes a non-`final` `<X>ComponentBase` and the level
writes the subclass that holds what it owns:

```swift
/// sourcery: DuetComponent, owns
protocol MainDependency: AnyObject { /* … */ }

final class MainComponent: MainComponentBase {
    lazy var feedAudioPlayer: FeedAudioPlaying = FeedAudioPlayer(
        memoryRepository: memoryRepository)   // reads the generated forwarders
}
```

Getting `owns` wrong is a compile error, not a silent defect: a `final class` cannot be subclassed,
and a stored property cannot be added in an extension.

**What it forwards.** Read-only and settable requirements, `async` / `throws` / `rethrows` methods,
effectful property requirements (`{ get async throws }`), `inout` and unlabelled parameters, generic
methods, `@escaping` / `@Sendable` closure parameters, and requirements inherited from a refined
protocol. Isolation follows the same rules as the mocks: the protocol's global actor lands on the
class, a `nonisolated` requirement is restated, and the storage becomes `nonisolated(unsafe)` where a
nonisolated forwarder has to read it.

**What it refuses**, each with a diagnostic naming the member: `static` requirements, `init`
requirements, `subscript` requirements, and associated types. None can be discharged by forwarding to
a stored instance, so generation fails rather than emitting a class that will not conform.

**The emitted type is internal by default**, even when the protocol is public — a Component is
consumed by its own module's builders, and widening a module's API surface as a side effect of
generating boilerplate is not a decision a template should make. `componentAccess = "public"` opts in.

Mocks and Components compose: a protocol annotated `/// sourcery: ProtocolMock, DuetComponent` gets the
double a spec drives *and* the production class that forwards. Both read the same isolation rules from
the same helpers, so they cannot disagree about which member is `nonisolated`.

## Tests

| lane | command | covers |
| --- | --- | --- |
| fast | `Tests/Checks/run-checks.sh` | snapshot of every template's generated output, both language modes, runtime behaviour. Mocks and Components are typechecked together, so the two cannot disagree about isolation. No simulator, no third-party packages, seconds |
| plugin | `Tests/Checks/run-plugin-checks.sh` | the SPM build-tool plugin, black-box over a fixture package: the derived source closure, the synthesized config, the defaults it supplies, and five red controls that must stay red. No simulator |
| xcode | `Tests/Checks/run-xcode-checks.sh` | the same plugin through `XcodeBuildToolPlugin`, over an Xcode project XcodeGen generates from a committed spec: config discovery, the one-directory expansion, a hand-listed `${SOURCERY_PROJECT}` entry, a target depending on a sibling target, and a bare template name that must fail. Needs `xcodegen`, no simulator |
| full | `Tests/Examples/ExampleProjectSpm/test-ios.sh` | RxSwift smart defaults, RIBs external annotation, type erasure, the SPM plugin. Needs an iOS Simulator |

All of them run on every push ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)), the fast lane
first. Run them locally before cutting a tag.

Release notes, including what each version changes in the generated output and what breaks:
[CHANGELOG.md](CHANGELOG.md). Working on the templates themselves — layout, where to change what, the
release procedure: [CONTRIBUTING.md](CONTRIBUTING.md).

## Rationale

Code-generation is an extremely powerful technique to improve the developer team's productivity by eliminating time-consuming
manual tasks, and ensuring consistency between different parts of the codebase. Typical examples include generating API wrappers
for database and network services, data structure representations as native types in a specific programming language, generating
test doubles and mocks for unit-testing, etc.

Due to Swift language's static nature and a (very) limited runtime reflection capabilities, it's arguably [the only modern language
with no mocking framework](https://blog.pragmaticengineer.com/swift-the-only-modern-language-with-no-mocking-framework/),
which makes it hard for development teams to apply patterns typical for more dynamic languages when writing unit-tests.

The common approach to improving developer's productivity has been to write tools that parse the source code of the program,
and automatically generate mock class definitions that can be later used in place of actual object's dependencies in unit tests,
to be able to instantiate the object in isolation from the rest of the system and test its behavior by analyzing side effects it
performs on dependencies. There are tools like [Sourcery](https://github.com/krzysztofzablocki/Sourcery),
[SwiftyMocky](https://github.com/MakeAWishFoundation/SwiftyMocky), [Cuckoo](https://github.com/Brightify/Cuckoo),
there's even a [plug-in](https://plugins.jetbrains.com/plugin/9601-swift-mock-generator-for-appcode) for the JetBrain's AppCode.
These tools and plug-ins are capable of auto-generating mock class definitions based on reading source type declarations,
however, I was personally struggling to find a comprehensive solution so far, that would cover some advanced coding patterns,
in particular, typical for programs that combine `RxSwift` and Uber's `RIBs` frameworks.

## Usage

### Swift Package Manager (SPM) prebuild plugin

A [prebuild SPM plugin](https://github.com/apple/swift-package-manager/blob/main/Documentation/Plugins.md#build-tool-plugins)
runs before the project is built, allowing to generate code based on the project source files.

1. To add the plugin to your project, add the plugin dependency to your `Package.swift`:

```swift
// Package.swift
// swift-tools-version: 5.9 // The minimum supported swift-tools version is 5.6
import PackageDescription

let package = Package(
  name: "YourPackageName",
  products: [
    // ...
  ],
  dependencies: [
    // ...
    .package(url: "https://github.com/modaal-agent/swift-sourcery-templates.git", from: "0.8.0"),
  ],
  targets: [
    .target(
      name: "YourTarget",
      dependencies: [
        // ...
      ],
      plugins: [
        .plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")
      ]
    ),
    .testTarget(
      name: "YourTargetTests",
      dependencies: [
        // ...
        .target(name: "ExampleProjectSpm"),
      ],
      plugins: [
        .plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")
      ]
    ),
  ]
)
```

The `SourcerySwiftCodegenPlugin` depends on a binary artifact bundle — [the one this repository
publishes](#the-released-artifact-bundle), which carries the Sourcery engine and the `templates/`
tree together, so resolving the package gets both at one version. The first time it is invoked,
Xcode/build system would ask for a permission to run the plugin.

You might also get an unverified developer warning when the plugin tries to invoke Sourcery for the first time.
To fix it, please use the [woraround](https://github.com/krzysztofzablocki/Sourcery/#issues) for removing Sourcery from quarantine:

```
xattr -dr com.apple.quarantine <...Derived Data Folder>/SourcePackages/artifacts/swift-sourcery-templates/sourcery/swift-sourcery-templates-<version>.artifactbundle/sourcery/bin/sourcery
```

2. Configuring code generation

Code generation is configured per target. Put a `*.sourcery*.yml` config file in the target's
source folder (refer to the [example project](Tests/Examples/ExampleProjectSpm/)):

<img src="/docs/img/sourcery_target_config.png" alt="Sourcery config files per target" style="height: 332px;"/>

Here, `ExampleProjectSpm` and `ExampleProjectSpmTests` are product targets for which code generation
is enabled. Type erasures should be available in the main target, mocks in the test target — so each
target carries its own config, and each target's generated files land on that target's compile path.

**A config says what to generate. The plugin supplies where.** The smallest config that works is
three lines:

```yml
# .Sourcery.Mocks.yml — beside the target it generates for
templates:
  - Mocks
```

That is a complete config. The plugin fills in the target's sources, the output directory the build
actually collects from, and — for a test target that directly depends on exactly one module of your
package — `args.testable`.

#### Where to read: the source closure

`${SOURCERY_SOURCES}` expands to the target's own sources **plus the recursive closure of its
dependencies**, first-party and external alike, one directory per module:

```yml
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_TARGET_MyModuleTests}/SourceryAnnotations   # a subset — yours to choose
```

This is what lets a mock carry requirements a protocol inherits from a module further down the graph.
A protocol refining one from a package your target reaches only through another package has no
`SOURCERY_TARGET_*` variable naming it, and no config could reach it before — the mock came out
missing those requirements, and the failure showed up as *"does not conform to protocol"* in the
consumer's build. `${SOURCERY_SOURCES}` closes that.

There are three ways a config can say what to read, and the plugin treats them differently:

| the config | what is scanned |
| --- | --- |
| no `sources:`, `project:` or `package:` key | the closure, appended by the plugin |
| `sources:` containing `- ${SOURCERY_SOURCES}` | the closure, **plus** every other entry in the list |
| `sources:` without the placeholder | exactly what is listed — the pre-0.3 behaviour, untouched |

`${SOURCERY_SOURCES}` is deliberately **not** an environment variable: nothing exports it, so if the
plugin ever failed to substitute it, Sourcery would report an unexpanded path rather than silently
scanning less than you meant.

#### Naming a template

A `templates:` entry can be the bare name of a template this package ships:

```yml
templates:
  - Mocks        # or Component, or TypeErase
```

A name is resolved in this order, first match winning:

1. it contains `/` or starts with `$` — a path, left as written;
2. a file of that exact name sits beside your config — yours wins, so a project with its own
   `Mocks.swifttemplate` keeps getting its own;
3. a template shipped by this package;
4. neither — the plugin warns, lists the shipped templates, and Sourcery then fails on it.

The shipped `templates/` directory in step 3 is whichever of these is a directory on disk, first one
winning, and the build log names the one that answered:

| | where it looks | works in |
| --- | --- | --- |
| 1 | this package in your dependency graph | a Swift package |
| 2 | the plugin's own source file, three components up | a package or an Xcode project |
| 3 | the artifact bundle `Package.swift` pins, beside the engine | a package or an Xcode project |

Routes 2 and 3 read no package graph, which is why a bare template name works in an Xcode project
too. At a released version all three name the same files: the bundle a tag pins was built from that
tag's own `templates/`.

`SOURCERY_TEMPLATES` is exported too, pointing at that directory, for a config that would rather
write the path itself.

#### Where to write

`output:` is the plugin's. A prebuild command's outputs are collected only from the directory it
declared, so a file generated anywhere else is written and then ignored — the target compiles without
it, and the failure surfaces as a missing type far from its cause. So:

- omit `output:` and the plugin supplies it;
- write `output: ${SOURCERY_OUTPUT_DIR}` and it resolves to the same directory;
- name any other directory and **the build fails**, naming both paths.

#### The options that stay yours

`args.import`, `args.excludedSwiftLintRules` and the choice of template have no single right answer,
so the plugin carries them through unread. `args.testable` is the one exception, and only where the
answer is unambiguous: for a test target with exactly one direct dependency on a module of your own
package, the plugin inserts `testable: [<module>]`. With none, or with two or more, it inserts
nothing and names the candidates in the build log.

#### One config, several templates

Sourcery writes one `<Template>.generated.swift` per `templates:` entry, so one config can drive
several:

```yml
# Sources/MyModule/.Sourcery.Components.yml
templates:
  - Component
  - TypeErase
```

A target may also carry several configs. Two configs of one target that name the same template are
rejected at plan time, naming both files — they would otherwise put two files declaring the same
types on one compile path.

#### Paths must be absolute

The plugin runs a *copy* of your config from its own work directory, and a relative path in a Sourcery
config resolves against the config file's own directory. So every path a rewritten config contains has
to be absolute. The exported variables already are, and the two rules above remove the reasons to
write a relative path at all. The plugin warns when it sees one; it does not rewrite it.

#### The exported variables

Every variable below keeps the name and value it has always had; `${SOURCERY_SOURCES}` and
`SOURCERY_TEMPLATES` are additions, and nothing was removed. A config written before 0.3 still means
exactly what it meant.

| variable | value |
| --- | --- |
| `SOURCERY_SOURCES` | *not a variable* — the placeholder the plugin expands to the source closure |
| `SOURCERY_TEMPLATES` | the shipped `templates/` directory |
| `SOURCERY_OUTPUT_DIR` | the directory this config's output is collected from |
| `SOURCERY_PACKAGE` | the root package directory (`SOURCERY_PROJECT` in an Xcode project) |
| `SOURCERY_TARGET_<target>` | that target's source directory |
| `SOURCERY_TARGET_<target>_DEP_<target>` | a directly-depended target's source directory |
| `SOURCERY_TARGET_<target>_DEP_<product>_MODULE_<module>` | a module of a directly-depended product |
| `SOURCERY_TARGET_<target>_DEP_<product>_TARGET_<target>` | a target of a directly-depended product |
| `GIT_ROOT` | `git rev-parse --show-toplevel` from the package directory |

The `_DEP_` variables are one level deep: they name a target's *direct* dependencies only. Reaching
further is what `${SOURCERY_SOURCES}` is for.

Every `SOURCERY_TARGET_*` variable is derived from the package graph, and an Xcode project has none —
so in an Xcode project the exported set is `SOURCERY_PROJECT`, `GIT_ROOT`, `SOURCERY_OUTPUT_DIR` and
`SOURCERY_TEMPLATES`, and nothing else. See [Xcode projects](#xcode-projects) below.

> [!NOTE]
> For the complete Sourcery config file reference, please refer to the [official documentation](https://krzysztofzablocki.github.io/Sourcery/).

#### Xcode projects

In an Xcode project (rather than a Swift package) the plugin runs through `XcodeBuildToolPlugin`,
which is handed no package graph. One feature degrades there, and the build log says so:

- `${SOURCERY_SOURCES}` expands to the target's own input-file directories, and to nothing else. The
  API reports no dependency edges to derive a closure from: `XcodeTarget.dependencies` was measured
  empty on Xcode 26.5 for a package product dependency as well as for a dependency on a sibling
  target in the same project. Name any other directory beside the placeholder, as an absolute path
  built from `${SOURCERY_PROJECT}`:

  ```yaml
  sources:
    - ${SOURCERY_SOURCES}
    - ${SOURCERY_PROJECT}/Libraries/Kit/Sources
  ```

Everything else works the same: the defaults, the `output:` check, the passthrough, and bare
template names — `SOURCERY_TEMPLATES` is exported here, and routes 2 and 3 of
[Naming a template](#naming-a-template) need no package graph, so `- Mocks` resolves as it does under
SPM. `Tests/Checks/run-xcode-checks.sh` builds an Xcode project on every push and checks all of it,
the degradation above included.

3. Finding the generated files

The plugin emits its invocation and what it derived to the build log:

<img src="/docs/img/command_invocation_log.png" alt="Command invocation log" style="height: 260px;"/>

The log names every exported environment variable, every default the plugin supplied and every
template name it resolved, so a config's effective meaning is always visible from the build alone.
Run `swift build -v` to see the remarks as well as the warnings.

### Standalone CLI (pre-generated mocks)

For projects that ship pre-generated mocks (so consumers don't need Sourcery installed), run the CLI directly:

```bash
sourcery \
  --sources Sources/MyModule \
  --templates /path/to/swift-sourcery-templates/templates/Mocks.swifttemplate \
  --output Sources/MyMocks/Generated/MyModuleMocks.swift \
  --args "import=Foundation,testable=MyModule"
```

Multiple `--args` flags can be used for additional imports:

```bash
sourcery \
  --args "import=Foundation,testable=MyModule" \
  --args "import=UIKit"
```

### The `mock-templates` CLI (fingerprinted output)

`mock-templates` wraps the invocation above and records provenance: the output file starts with a
fingerprint block naming the template bundle tag, the generator config, the path and SHA-256 of every
scanned source file, and the SHA-256 of the generated body below the block. A repo that commits its
generated mocks can then prove them current without running Sourcery — no engine download, no
first-use template compile — which is what a cold CI job wants. Generation is deterministic, so
fingerprint-current implies output-current.

Build it from this package: `swift build --product mock-templates`.

```bash
# Generate: runs sourcery, then writes the output under its fingerprint.
mock-templates generate \
  --sourcery /path/to/sourcery \
  --templates /path/to/swift-sourcery-templates/templates/Mocks.swifttemplate \
  --sources Sources/MyModule \
  --args "import=Foundation,testable=MyModule" \
  --bundle-version 0.6.0 \
  --root "$(pwd)" \
  --output Tests/MyModuleTests/Generated/MyModuleMocks.swift

# Validate: re-hashes the recorded inputs and the body. No Sourcery involved.
mock-templates validate \
  --file Tests/MyModuleTests/Generated/MyModuleMocks.swift \
  --root "$(pwd)" \
  --sources Sources/MyModule \
  --expect-bundle 0.7.0 \
  --template Mocks.swifttemplate \
  --args "import=Foundation,testable=MyModule"
```

`validate` fails on: a listed file whose content changed, a listed file that is gone, a `.swift` file
present under `--sources` but absent from the block (a file added after generation), a body whose
hash differs from the recorded one (a hand-edit), with `--expect-bundle` a block imprinted
by a different bundle tag, and with `--template` a block whose config line names a different
template or a different arg list from the one the caller passes. `imprint` rewrites the block over
the existing body without regenerating. `generate --disable-cache` passes `--disableCache` through
to Sourcery.

Pass `--template` and the same `--args` the generating config holds to cover the two generation
inputs the recorded hashes do not: the template that drove the file and the arguments it was given.
The line records the template by basename, so a name and a path to it are the same config, and the
arguments are sorted, so their order in a config does not move it. Both flags are optional —
`validate` with neither checks the inputs, the body and the bundle tag, as it does above. `--args`
without `--template` is an error: the config line names the template first.

Recorded paths are relative to `--root`, so the block reproduces across checkouts; a source outside
the root is an error, never an absolute path. The tool is policy-free: which sources a generated
file scans, and which bundle tag to expect, are the calling script's to decide.

### The released artifact bundle

Each release publishes one download that carries everything a generating repo needs — the Sourcery
engine at the version the templates are checked against (universal macOS binary), the `templates/`
tree, and the `mock-templates` CLI — so the engine and the templates are pinned together by a single
tag and there is no pair of versions to keep matched:

```bash
VERSION=0.6.0
BASE=https://github.com/modaal-agent/swift-sourcery-templates/releases/download/$VERSION
curl -fsSLO "$BASE/swift-sourcery-templates-$VERSION.artifactbundle.zip"
curl -fsSLO "$BASE/swift-sourcery-templates-$VERSION.artifactbundle.zip.sha256"
shasum -a 256 -c "swift-sourcery-templates-$VERSION.artifactbundle.zip.sha256"
unzip -q "swift-sourcery-templates-$VERSION.artifactbundle.zip"

BUNDLE="swift-sourcery-templates-$VERSION.artifactbundle"
"$BUNDLE/mock-templates/bin/mock-templates" generate \
  --sourcery "$BUNDLE/sourcery/bin/sourcery" \
  --templates "$BUNDLE/templates/Mocks.swifttemplate" \
  ...
```

A CI lane that only runs `validate` doesn't need the ~60 MB engine: `mock-templates-<version>-macos.zip`
is the CLI alone, published beside the bundle with its own `.sha256`.

The bundle is a SwiftPM artifact bundle whose `info.json` declares both executables, so a
`binaryTarget` pointed at the zip resolves `sourcery` or `mock-templates` by artifact name; the
published SHA-256 is the `checksum:` value such a target needs. `Scripts/assemble-release.sh`
builds the assets; `.github/workflows/release.yml` runs it on every tag push and attaches them to
the tag's GitHub release.

**The plugin resolves this bundle too.** `Package.swift`'s `sourcery` binaryTarget names it rather
than upstream Sourcery's, so a consumer of the prebuild plugin downloads the engine and
`templates/` in the one zip, and the plugin reads its bare template names out of it when neither the
package graph nor the plugin's own source location yields a `templates/` directory — which is the
case for an Xcode project consuming this package from its URL. One consequence for a consumer
driving the plugin with a `.ejs` template of their own: this bundle does not carry upstream's
`bin/ejs.js`, because every template here is a `.swifttemplate`.

### Template arguments

Passed via `--args` on the CLI or `args:` in a YAML config:

| Arg | Effect |
|-----|--------|
| `import=Module` | add `import Module` to the generated file |
| `testable=Module` | add `@testable import Module` to the generated file |
| `excludedSwiftLintRules=[rule1,rule2]` | emit `//swiftlint:disable` directives for each rule |

A Component is production code, so its output takes `import=`, not `testable=`.

## Agent skill

`skills/swift-sourcery-mocks/` is an [agent skill](https://code.claude.com/docs/en/skills): the
setup above, written for a coding agent working in a repository that *adopts* these templates. It
picks the lane, writes the config, and names the cause when generation produces a mock that does not
conform. Its annotation table is rendered from the same registry this README's is
(`Scripts/render-annotations.sh`), so the two cannot drift apart.

Four channels install it, over one tree.

**1. Any of ~75 agents, through the cross-agent CLI.** `-g` installs for every project on the
machine instead of this one; `--list` lists without installing.

```bash
npx skills add modaal-agent/swift-sourcery-templates
```

**2. As a Claude Code plugin.** The repository root is both the marketplace and the plugin:

```
/plugin marketplace add modaal-agent/swift-sourcery-templates
/plugin install swift-sourcery-mocks@swift-sourcery-templates
```

**3. By hand.**

```bash
git clone https://github.com/modaal-agent/swift-sourcery-templates
cp -r swift-sourcery-templates/skills/* ~/.claude/skills/     # or .claude/skills/ per project
```

**4. claude.ai and the Skills API.** The frontmatter carries only the Agent Skills standard's keys,
so `skills/swift-sourcery-mocks/` packages and uploads unedited.

The skill is not a release asset. All four channels read this repository, so a change to it is
published by landing on `master`; `Tests/Checks/run-skill-checks.sh` gates it on every push,
including the check that every `SOURCERY_*` variable and every `mock-templates` flag it names is one
this repository actually provides.

## Annotating External Protocols

To generate mocks for protocols defined in external packages (without modifying their source), use empty extensions with the `ProtocolMock` annotation:

```swift
// In your SourceryAnnotations/ directory:
import ExternalFramework

/// sourcery: ProtocolMock
extension ExternalProtocol {}

/// sourcery: ProtocolMock
extension AnotherProtocol {}
```

Sourcery picks up annotations from extensions on the protocol. Pass the annotations directory as an additional `--sources` path. This pattern keeps the public API files clean — no `/// sourcery:` annotations in protocol definitions.

## Annotations Reference

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

`ProtocolMock`, `ObjcProtocolMock` and `TypeErasure` were previously spelled `CreateMock`,
`ObjcProtocol` and `TypeErase`. Those spellings still select the same template, and a release after
this one stops accepting them — see [CHANGELOG.md](CHANGELOG.md).

# License

    Copyright 2018 Ivan Misuno

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
