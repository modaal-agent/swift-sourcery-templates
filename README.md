# swift-sourcery-templates

[![CI](https://github.com/ivanmisuno/swift-sourcery-templates/actions/workflows/ci.yml/badge.svg)](https://github.com/ivanmisuno/swift-sourcery-templates/actions/workflows/ci.yml)

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
/// sourcery: CreateMock
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
and under `-swift-version 6` — see [`Checks/`](Checks).

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
/// sourcery: CreateMock
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

Mocks and Components compose: a protocol annotated `/// sourcery: CreateMock, DuetComponent` gets the
double a spec drives *and* the production class that forwards. Both read the same isolation rules from
the same helpers, so they cannot disagree about which member is `nonisolated`.

## Tests

| lane | command | covers |
| --- | --- | --- |
| fast | `Checks/run-checks.sh` | snapshot of every template's generated output, both language modes, runtime behaviour. Mocks and Components are typechecked together, so the two cannot disagree about isolation. No simulator, no third-party packages, seconds |
| full | `Examples/ExampleProjectSpm/test-ios.sh` | RxSwift smart defaults, RIBs external annotation, type erasure, the SPM plugin. Needs an iOS Simulator |

Both run on every push ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)), the fast lane first.
Run both locally before cutting a tag.

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
    .package(url: "https://github.com/ivanmisuno/swift-sourcery-templates.git", from: "0.2.2"),
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

The `SourcerySwiftCodegenPlugin` depends on the binary distribution of the Sourcery CLI.
The first time it is invoked, Xcode/build system would ask for a permission to run the plugin.

You might also get an unverified developer warning when the plugin tries to invoke Sourcery for the first time.
To fix it, please use the [woraround](https://github.com/krzysztofzablocki/Sourcery/#issues) for removing Sourcery from quarantine:

```
xattr -dr com.apple.quarantine <...Derived Data Folder>/SourcePackages/checkouts/swift-sourcery-templates/Plugins/Sourcery/sourcery.artifactbundle/sourcery/bin/sourcery
```

2. Configuring code generation

The codegeneration is configured per target in an SPM project. Put a `*.sourcery.yml` config file in the target's source folder
(refer to the [example project](Examples/ExampleProjectSpm/)):

<img src="/docs/img/sourcery_target_config.png" alt="Sourcery config files per target" style="height: 332px;"/>

Here, `ExampleProjectSpm` and `ExampleProjectSpmTests` are product targets, for which we want to enable code generation.
We want to generate type erasures and interface mocks. Type erasure classes should be available for use in the main target,
while mocks should be available in the test target.

Here is caveat: Some mock classes should be generated for interfaces that are declared in external packages (e.g. for the `RIBs` package).
We need to (a) include the external package sources in the config file:

```
# .Sourcery.Mocks.yml
sources:
  - ${SOURCERY_TARGET_ExampleProjectSpm}
  - ${SOURCERY_TARGET_ExampleProjectSpmTests}/SourceryAnnotations
  - ${SOURCERY_TARGET_ExampleProjectSpm_DEP_RIBs_MODULE_RIBs}
```

We're doing a little trickery here to work around an issue with Sourcery — when invoked from a build tool SPM plugin,
Sourcery cannot analyze the package structure, so the plugin exports the package structure via environment variables.
In the excample above:

- `SOURCERY_TARGET_ExampleProjectSpm` refers to the `ExampleProjectSpm` target source location;
- `SOURCERY_TARGET_ExampleProjectSpmTests` refers to the `ExampleProjectSpmTests` target source location;
- `SOURCERY_TARGET_ExampleProjectSpm_DEP_RIBs_MODULE_RIBs` refers to the `RIBs` module source location (`RIBs` is the dependency of the `ExampleProjectSpm` target).

The plugin exports all package dependencies' source locations via environment variable similarly:

- `SOURCERY_TARGET_<target_name>_DEP_<dependecy_module>_MODULE_RIBs`
- `SOURCERY_TARGET_<target_name>_DEP_<dependecy_target>_TARGET_RIBs`

> [!NOTE]
> For the complete Sourcery config file reference, please refer to the [official documentation](https://krzysztofzablocki.github.io/Sourcery/).

3. Finding the generated files

The above might seem tricky at first. The plugin helps debug setup issues by emitting invocation and debug logs to the build log:

<img src="/docs/img/command_invocation_log.png" alt="Command invocation log" style="height: 260px;"/>

The invocation log also contains all exported environment variables for the dependencies.

### Podfile

_Following examples refer to the [tutorial project](https://github.com/ivanmisuno/Tutorial_RIBs_CodeGeneration) (WIP),
please feel free to clone and see its workings. Accompanying blog post is coming._

1. Add `SwiftMockTemplates` Pod to your projects's Test target:

   ```Podfile
   pod 'SwiftMockTemplates', :git => 'https://github.com/ivanmisuno/swift-sourcery-templates.git', :tag => '0.1.0'
   ```

   (I'll release it as a public Podspec once I complete unit-tests).

2. Add `.sourcery-mocks.yml` config file to the project's root:

   ```yml
   sources:
     - Tutorial_RIBs_CodeGeneration
     - Tutorial_RIBs_CodeGenerationTests/Mocks/AnnotatedRIBsProtocols.swift
     - Pods/RIBs
   templates:
     - Pods/SwiftMockTemplates/templates/Mocks.swifttemplate
   output: Tutorial_RIBs_CodeGenerationTests/Mocks
   args:
     testable:
       - Tutorial_RIBs_CodeGeneration
     import:
       - RIBs
       - RxSwift
       - RxTest
     excludedSwiftLintRules:
       - force_cast
       - function_body_length
       - line_length
       - vertical_whitespace
   ```

3. Add `codegen.sh` script that will run `Sourcery` with the above config file:

   ```sh
   #!/bin/bash

   # the directory of the script. all locations are relative to the $DIR
   DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
   PARENT_DIR="$DIR/.."

   SOURCERY_DIR="$PARENT_DIR/Pods/Sourcery"
   SOURCERY="$SOURCERY_DIR/bin/sourcery"

   "$SOURCERY" --config "$PARENT_DIR"/.sourcery-mocks.yml $1 $2
   ```

   Note that `sourcery` executable is installed in `Pods` folder.

4. Annotate protocols in your code for which you'd like to generate mock classes with the following annotation:

   ```Swift
   /// sourcery: CreateMock
   ```

   There are more advanced use cases, the documentation is coming.

5. Run following command to generate mock classes:

   ```sh
   scripts $ ./codegen.sh [--disableCache]
   ```

   This command will generate `Mocks.generated.swift` file in the `output` folder as specified in the config file.

6. Add the generated file to the test target in the Xcode project.

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

### Template arguments

Passed via `--args` on the CLI or `args:` in a YAML config:

| Arg | Effect |
|-----|--------|
| `import=Module` | add `import Module` to the generated file |
| `testable=Module` | add `@testable import Module` to the generated file |
| `excludedSwiftLintRules=[rule1,rule2]` | emit `//swiftlint:disable` directives for each rule |

A Component is production code, so its output takes `import=`, not `testable=`.

## Annotating External Protocols

To generate mocks for protocols defined in external packages (without modifying their source), use empty extensions with the `CreateMock` annotation:

```swift
// In your SourceryAnnotations/ directory:
import ExternalFramework

/// sourcery: CreateMock
extension ExternalProtocol {}

/// sourcery: CreateMock
extension AnotherProtocol {}
```

Sourcery picks up annotations from extensions on the protocol. Pass the annotations directory as an additional `--sources` path. This pattern keeps the public API files clean — no `/// sourcery:` annotations in protocol definitions.

## Annotations Reference

| Annotation | Target | Effect |
|------------|--------|--------|
| `CreateMock` | Protocol / extension | Generate mock class |
| `TypeErase` | Protocol | Generate type erasure wrapper |
| `associatedType = "T: Constraint"` | Protocol | Associated type for type erasure |
| `genericType = "T: Constraint"` | Method | Generic type parameter |
| `annotatedGenericTypes = "{T}"` | Parameter | Generic placeholder marker |
| `methodName = "customName"` | Method | Override mock variable name |
| `const` | Variable | Use `let` in mock |
| `init` | Variable | Include in mock initializer |
| `handler` | Variable | Generate handler closure |
| `import = "Module"` | Protocol | Add `import` to output |
| `ObjcProtocol` | Protocol | Add `NSObject` superclass |
| `globalActor = "MyIsolation"` | Protocol | Declare the mock's global actor when the attribute name does not end in `Actor` |
| `uncheckedSendable` | Protocol | Force `@unchecked Sendable` on the mock when the `Sendable` refinement is not visible to Sourcery |
| `subject = "CurrentValue"` / `"Passthrough"` | Variable / method | Choose the subject backing an `AnyPublisher` member |
| `skipArgumentRecording` | Protocol / method | Do not generate `<method>Args`; call counting and the handler are unaffected |
| `DuetComponent` | Protocol | Generate the forwarding Component class |
| `owns` | Protocol | Emit `<X>ComponentBase` (non-final) for a hand-written subclass that holds what the level owns |
| `componentName = "Foo"` | Protocol | Name the emitted Component `Foo` instead of deriving it from the protocol |
| `componentAccess = "public"` | Protocol | Emit a `public` Component; the default is internal |

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
