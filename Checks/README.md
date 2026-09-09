# Checks — the fast lane, and the plugin lane

`run-checks.sh` and `run-cli-checks.sh` cover the templates and the CLI;
`run-plugin-checks.sh` covers the build-tool plugin over its own fixture packages.
The fast lane comes first.

## The fast lane

`./run-checks.sh` runs every template in its `TEMPLATES` list over
[`Fixtures/`](Fixtures) and holds the results to four gates. It needs no
simulator and no third-party package, so it runs in a few seconds and is the loop
to use while editing `templates/`.

```bash
Checks/run-checks.sh              # run the gates
Checks/run-checks.sh --record     # rewrite the snapshots, then run the gates
SOURCERY=/path/to/sourcery Checks/run-checks.sh
```

| gate | what it proves |
| --- | --- |
| **snapshot** | each generated file matches its recording in [`Snapshots/`](Snapshots), so every template change shows up as a reviewable diff of real output |
| **zero-match** | a scan with no matching annotation still writes the file — the generators emit a marker comment, because the engine skips whitespace-only renders and consumers commit + fingerprint the output — snapshotted as `ZeroMatch-*` |
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
[`Examples/ExampleProjectSpm`](../Examples/ExampleProjectSpm) — run
`./test-ios.sh` there. The build-tool plugin has a lane of its own, below. Run
all of them before cutting a tag.

# The plugin lane

```bash
Checks/run-plugin-checks.sh          # ~1 min cold, no simulator
Checks/run-plugin-checks.sh --keep   # keep the plugin outputs too (faster, less cold)
```

A build-tool plugin may not depend on a library target, so no test target can
import [`SourcerySwiftCodegenPlugin.swift`](../Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift).
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

## The red controls

[`PluginFixtureRed/`](PluginFixtureRed) holds four packages that must **fail**,
each matched on its diagnostic. One package each: build planning runs every
target's plugin, so a plan-time error in one target fails the build for all of
them and no `--target` can isolate it.

| package | must fail because |
| --- | --- |
| `WrongOutput` | its `output:` names a directory the build does not collect from — the error names both paths |
| `Collision` | two configs of one target name the same template, so both would put files declaring the same types on one compile path |
| `UnknownTemplate` | its `templates:` entry names nothing; the plugin warns and lists the shipped templates, then Sourcery fails |
| `PackageKey` | it declares `package:` in place of `sources:`; the gate is that **no** `sources:` block was appended over it |

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
