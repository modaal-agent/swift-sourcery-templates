# Checks — the fast lane, the plugin lane and the Xcode lane

`run-checks.sh` and `run-cli-checks.sh` cover the templates and the CLI;
`run-plugin-checks.sh` covers the build-tool plugin's SwiftPM path over its own
fixture packages, and `run-xcode-checks.sh` covers its Xcode path over a
generated Xcode project. The fast lane comes first.

## The fast lane

`./run-checks.sh` runs every template in its `TEMPLATES` list over
[`Fixtures/`](Fixtures) and holds the results to five gates. It needs no
simulator and no third-party package, so it runs in a few seconds and is the loop
to use while editing `templates/`.

```bash
Tests/Checks/run-checks.sh              # run the gates
Tests/Checks/run-checks.sh --record     # rewrite the snapshots, then run the gates
SOURCERY=/path/to/sourcery Tests/Checks/run-checks.sh
```

| gate | what it proves |
| --- | --- |
| **snapshot** | each generated file matches its recording in [`Snapshots/`](Snapshots), so every template change shows up as a reviewable diff of real output |
| **zero-match** | a scan with no matching annotation still writes the file — the generators emit a marker comment, because the engine skips whitespace-only renders and consumers commit + fingerprint the output — snapshotted as `ZeroMatch-*` |
| **near-miss** | a selector whose spelling differs from the registry's only in case fails the run, naming the type, the spelling found and the canonical form; an option that does writes one `// sourcery-templates:` comment into the generated file and generation continues |
| **typecheck** | all of them compile **together** with **zero diagnostics** under `-swift-version 5 -strict-concurrency=complete` **and** under `-swift-version 6` |
| **behaviour** | the mocks count calls, record arguments, run handlers, suspend where the protocol suspends and deliver values pushed into their subjects; the Components forward to the parent and hold what the level owns — [`Behaviour/Main.swift`](Behaviour/Main.swift), plain assertions in one executable |

Compiling every template's output in one invocation is deliberate: a mock and a
Component of the same protocol have to agree about which member is `nonisolated`
and which class carries a global actor. One typecheck is what checks that.

The snapshot is the reason to run `--record` deliberately: a template edit that
changes output for a shape you were not thinking about shows up in the diff
instead of reaching consumers.

## What the fixtures cover

Every protocol in `Fixtures/` is a shape taken from a consumer, not an invented
one. [`Composition.swift`](Fixtures/Composition.swift),
[`Isolation.swift`](Fixtures/Isolation.swift) and
[`Streams.swift`](Fixtures/Streams.swift) mirror the Duet reference app:
a `<X>Dependency` protocol per composition level, `@MainActor` repositories, a
`nonisolated` subtree port, `async` staging seams, `AnyPublisher` state streams,
and registration methods returning `AnyCancellable`.

| construct | fixture |
| --- | --- |
| `@MainActor` protocol | `UserRepositoryProtocol`, `AppServicesRegistering` |
| `nonisolated` member of an isolated protocol | `PushNotificationRepositoryProtocol` |
| `async`, `async throws`, `throws` | `MediaStaging`, `AudioSessionConfiguring` |
| `Sendable` refinement | `AnalyticsTracking` |
| member-level `@MainActor` on a non-isolated protocol | `TimelineBuildable` |
| `@escaping` closure parameter | `AudioSessionConfiguring` |
| `@Sendable` closure parameter | `UploadScheduling` |
| `AnyPublisher` variable and method | `MemoryRepositoryProtocol` |
| element type with no default value (same subject as one with a default) | `MemoryEventStreaming` |
| a method whose `Output` has a default value — never seeded | `MemoryRepositoryProtocol.share` |
| `subject` annotation override | `NotificationSignalling`, and `MemoryRepositoryProtocol.token` for the override on a method |
| protocol inheritance / composite | `AppServicesRegistering` |
| empty protocol | `RootDependency` |
| requirement with no synthesizable default | `TimelineDependency` (five of them) |
| optional existential — property, parameter, return type, nested in a closure | `DetailPresenting` |
| optional protocol composition | `DetailPresenting.policy` |
| non-optional existential in an array (must NOT gain parentheses) | `DetailPresenting.presentAll` |

[`Recording.swift`](Fixtures/Recording.swift) adds what the recorded-argument
arrays have to get right. Every mocked method in the directory contributes its
own `<method>Args` to the snapshot, so this file carries only the shapes where
that array is not simply `[T]`.

| construct | fixture |
| --- | --- |
| `nonisolated` member of an isolated protocol — array is `nonisolated(unsafe)` | `DiagnosticsReporting.report` |
| two parameters, one optional — one labelled tuple per call | `DiagnosticsReporting.report` |
| `inout` parameter — the element type drops it | `DiagnosticsReporting.accumulate` |
| no parameters — no array | `DiagnosticsReporting.flush` |
| closure parameter skipped, its value siblings recorded | `UploadScheduling.schedule` |
| closure-only parameter list — no array | `AudioSessionConfiguring.requestRecordPermission` |
| `skipArgumentRecording` on a method | `PlaybackObserving.adopt` |
| `skipArgumentRecording` on the protocol | `PlaybackRetaining` |

The generic case is not here: a generic method records nothing, and the
annotated-generic protocols that would prove it live in the example project (a
mocked generic method needs `annotatedGenericTypes` to produce a usable double
at all). The example lane is what covers it.

[`Forwarding.swift`](Fixtures/Forwarding.swift) adds the shapes the Component
template has to forward. Two of its protocols carry `DuetComponent` alone, each
saying why the mock template does not see it.

| construct | fixture |
| --- | --- |
| a level that owns nothing — the whole class is generated | `TimelineDependency` |
| a level that owns something — `owns`, base class, hand-written subclass | `MainDependency` / `MainComponent` |
| settable requirement (`{ get set }`) | `CaptureDependency` |
| `nonisolated` port on an isolated level | `CaptureDependency` |
| `async throws` method | `CaptureDependency` |
| unlabelled, differently-labelled, `inout`, generic, `rethrows` | `RegistrationDependency` |
| `@escaping @Sendable` closure parameter | `RegistrationDependency` |
| effectful property (`{ get async throws }`) | `ProfileDependency` |
| `componentName` / `componentAccess` overrides | `OnboardingFlowDependency` |

[`Vocabulary.swift`](Fixtures/Vocabulary.swift) covers which spelling selects
which template. Every other fixture writes `CreateMock`, the spelling that
shipped and is now an alias, so without this file the canonical names appear in
no generated output.

| construct | fixture |
| --- | --- |
| the canonical mock selector | `VocabularyCanonical` |
| `ObjcProtocolMock` standing alone — an `NSObject` mock from one annotation | `VocabularyObjc` |
| the `CreateMock` + `ObjcProtocol` pair a consumer's source still carries | `VocabularyLegacyObjc` |

A misspelling is not here: it fails generation for the whole run, so it lives in
`run-checks.sh`'s near-miss section and in `PluginFixtureRed/NearMiss`.
| a Component name not derived from a `Dependency` suffix | `AppServicesRegistering` |
| optional existentials in a forwarded signature | `DetailPresenting` |

Four constructs are refused rather than emitted — `static`, `init` and
`subscript` requirements, and associated types. They are checked as negative
controls rather than fixtures: generation fails, so a fixture carrying one would
fail the whole lane.

## Adding a check to the fast lane

1. Add the protocol shape to the fixture file it belongs in. If it comes from a
   consumer, say which one in a comment — a fixture nobody has in production is
   a shape nobody has to support.
2. Run `./run-checks.sh --record` and **read the snapshot diff**. That diff is
   the review: it is the only place the generated output is visible.
3. Add a behaviour check if the shape has runtime semantics (a stream to drive,
   a suspension to observe, a counter to assert).

## What this lane does not cover

RxSwift smart defaults (`Single`, `Observable`, `AnyObserver`, `Disposable`),
RIBs protocol annotation and type erasure. Those need the dependencies and the
simulator, and they live in
[`Tests/Examples/ExampleProjectSpm`](../Examples/ExampleProjectSpm) — run
`./test-ios.sh` there. The build-tool plugin has two lanes of its own below, one
per plugin API. Run all of them before cutting a tag.

# The plugin lane

```bash
Tests/Checks/run-plugin-checks.sh          # ~1 min cold, no simulator
Tests/Checks/run-plugin-checks.sh --keep   # keep the plugin outputs too (faster, less cold)
```

A build-tool plugin may not depend on a library target, so no test target can
import [`SourcerySwiftCodegenPlugin.swift`](../../Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift).
Every gate is therefore black-box: build a fixture package, then read the
synthesized configs under `.sourceryConfigs/`, the generated code under
`.generatedFiles/`, and the build's own outcome.

## The green package

[`PluginFixture/`](PluginFixture) must build. Its shape is the chain
`App` → `Middle` → `Leaf`, with `ExternalKit` arriving through `Middle` from a
second package — so `Leaf` and `ExternalKit` sit two levels from `App`, which is
exactly the distance no `SOURCERY_TARGET_*` variable reaches.

| target | config shape it carries |
| --- | --- |
| `App` | the placeholder plus one hand-listed entry, and two shipped templates named by name from one config |
| `Solo` | zero configuration: `templates:` and nothing else |
| `Verbatim` | declares every path itself — the copy must be byte-identical |
| `Local` | ships its own `Mocks.swifttemplate` beside its config, which has to outrank the shipped one |
| `AppTests` | a test target with one direct root-package dependency, and *two* configs |
| `AmbiguousTests` | a test target with two, so `args.testable` cannot be derived |

| gate | what it proves |
| --- | --- |
| **splice** | `${SOURCERY_SOURCES}` expands to one quoted, absolute directory per module in the closure, sorted, with `Leaf` and `ExternalKit` present — the case no env var can express |
| **passthrough** | every other line of the config, comments and blank lines included, survives in order |
| **defaults** | a config carrying only `templates:` gains a `sources:` block holding the closure and an `output:` holding the absolute output directory, and generates |
| **no-defaults** | a config declaring both keys is copied byte for byte |
| **testable** | one direct root-package dependency inserts `testable: [<module>]` at the siblings' indentation; two insert nothing and name both; a config that already declares it is untouched; no non-test target gets one |
| **bare name** | `- Mocks` resolves to the shipped template; a file beside the config wins over the shipped one of the same name, and it is the local one that runs |
| **generation** | the mock for the `Leaf`-refining protocol carries `save` (two modules away), `report` (two modules away, another package), `cacheLimit` and `profileID`, and the fixture's tests pass against it |
| **determinism** | a second build leaves every synthesized config byte-identical — the prebuild command re-runs every build, and a config that churns invalidates Sourcery's cache every time |
| **shared cache** | a target with two configs, rebuilt with the caches dropped, produces the same output both times |

## The artifact-bundle route

[`PluginFixtureBundleRoute/`](PluginFixtureBundleRoute) is the only place route 3
of the template-resolution order runs — the plugin reading `templates/` out of
the artifact bundle `Package.swift` pins.

Every other fixture reaches this repository directly, so the plugin's own source
file sits beside a `templates/` directory and `#filePath` answers first. That is
what a branch wants, and it leaves the bundle route covered by nothing. This
fixture's dependency is therefore a copy of the repository with `templates/` left
out, which `run-plugin-checks.sh` writes into `.build/plugin-checks/engine-package`
before building: route 1 finds the package in the graph with no templates under
it, route 2 finds none beside the plugin source, and route 3 answers.

| gate | what it proves |
| --- | --- |
| **bundle route** | the build succeeds, the log names the pinned artifact bundle as the route, the resolved template path is inside an `.artifactbundle` rather than in this working tree, and the mock the bundle's template generated carries `func ferry` |

The copy is generated rather than committed: it is this repository minus one
directory, and a second copy in the tree would be a second thing to keep in step.
Restoring `templates/` into it turns the route back to the package graph, which
is the negative control — the log then reads `the package graph` and both path
assertions fail.

## The red controls

[`PluginFixtureRed/`](PluginFixtureRed) holds five packages that must **fail**,
each matched on its diagnostic. One package each: build planning runs every
target's plugin, so a plan-time error in one target fails the build for all of
them and no `--target` can isolate it.

| package | must fail because |
| --- | --- |
| `WrongOutput` | its `output:` names a directory the build does not collect from — the error names both paths |
| `Collision` | two configs of one target name the same template, so both would put files declaring the same types on one compile path |
| `UnknownTemplate` | its `templates:` entry names nothing; the plugin warns and lists the shipped templates, then Sourcery fails |
| `PackageKey` | it declares `package:` in place of `sources:`; the gate is that **no** `sources:` block was appended over it |
| `NearMiss` | its protocol is annotated `protocolmock`, which is not `ProtocolMock` — names are matched exactly, including case, and the error names the type and the canonical spelling |

A red control that stops failing is a gate that stopped gating, so each one
matches on the diagnostic text, not merely on a non-zero exit.

## Adding a check to the plugin lane

1. Decide whether the new rule is green or red. Green means a config shape that
   must work: add a target to `PluginFixture` carrying it, one target per shape,
   so each target's failure names the shape it broke.
2. Red means a config the plugin must refuse: add a package under
   `PluginFixtureRed/`, never a target beside a green one — a plan-time error
   fails the whole package, so a red control has to be alone.
3. Assert on the diagnostic text, not just on the exit status.

# The Xcode lane

```bash
Tests/Checks/run-xcode-checks.sh          # ~35s, no simulator
Tests/Checks/run-xcode-checks.sh --keep   # keep the build outputs too (faster, less cold)
```

Needs [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.

The plugin lane above runs the plugin through `PackagePlugin`. An Xcode project
runs it through `XcodeBuildToolPlugin` instead, and that API is handed no package
graph, no dependency edges and no shipped templates, so almost nothing the plugin
lane asserts carries over. This lane is the only place the `XcodeProjectPlugin`
half of
[`SourcerySwiftCodegenPlugin.swift`](../../Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift)
is run rather than only typechecked.

## The green project

[`XcodeFixture/`](XcodeFixture) is four macOS framework targets, built one scheme
at a time. Its `.xcodeproj` is generated by `xcodegen` from
[`xcodegen.yml`](XcodeFixture/xcodegen.yml) on every run and is not committed:
the spec is 70-odd lines a reviewer can read, and the `project.pbxproj` it
produces is generated identifiers. macOS frameworks rather than an iOS app
because the plugin path under test does not vary by platform, and this way the
lane needs no simulator, no signing and no `Info.plist`.

| target | what it carries |
| --- | --- |
| `App` | the placeholder plus one hand-listed `${SOURCERY_PROJECT}` entry, and a dependency on a local package's product |
| `Solo` | zero configuration: `templates:` and nothing else |
| `Core` | no plugin and no config — it exists to be depended on |
| `Dependent` | a dependency on `Core`, which is a sibling target in the same project |

| gate | what it proves |
| --- | --- |
| **runs** | the config is discovered through the target's own directory, a synthesized copy is written with `output:` supplied, Sourcery runs, and the generated file is in the target's compile input list |
| **closure** | the spliced `sources:` block is exactly the target's own input directory — `App` depends on a package product and that contributes nothing, because `XcodeTarget.dependencies` is empty for a package product as well as for a sibling target |
| **hand-listed** | the one `${SOURCERY_PROJECT}`-rooted line the author wrote is scanned, and the mock carries `cacheLimit` (one module away) and `report` (two, through the first) |
| **passthrough** | every other line of the config, comments included, survives in order |
| **defaults** | a config carrying only `templates:` gains `sources:` and `output:`, and generates |
| **determinism** | a second build leaves every synthesized config byte-identical |
| **sibling target** | a target depending on a second target in the same project builds |

The **closure** gate asserts a degradation rather than a feature. That is
deliberate: the expansion being one directory is a fact about an API that may
change, and a gate that reads the synthesized config reports the change instead
of silently getting better.

## The red control

[`XcodeFixtureRed/BareName/`](XcodeFixtureRed/BareName) must **fail**, matched on
its diagnostic: its `templates:` names `Mocks`, and an Xcode project has no
package graph to resolve a shipped template against. A project of its own, for
the reason the plugin lane's red controls are separate packages — build planning
runs the plugin for every target being built.

## Adding a check to the Xcode lane

1. Green means a project shape that must work: add a target to
   `XcodeFixture/xcodegen.yml` carrying it, plus a scheme, so the lane can build
   it alone and a failure names the shape it broke.
2. Red means a project the plugin must refuse: add a directory under
   `XcodeFixtureRed/` with its own `xcodegen.yml`, never a target beside a green
   one.
3. Assert on the diagnostic text, not just on the exit status.
