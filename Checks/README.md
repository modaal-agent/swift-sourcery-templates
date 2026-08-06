# Checks — the fast lane

`./run-checks.sh` runs every template in its `TEMPLATES` list over
[`Fixtures/`](Fixtures) and holds the results to three gates. It needs no
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
[`Streams.swift`](Fixtures/Streams.swift) mirror the WikiMemory reference app:
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
| element type with no default value | `MemoryEventStreaming` |
| `subject` annotation override | `NotificationSignalling` |
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

## What this lane does not cover

RxSwift smart defaults (`Single`, `Observable`, `AnyObserver`, `Disposable`),
RIBs protocol annotation, type erasure, and the SPM build-tool plugin. Those
need the dependencies and the simulator, and they live in
[`Examples/ExampleProjectSpm`](../Examples/ExampleProjectSpm) — run
`./test-ios.sh` there. Run both before cutting a tag.

## Adding a check

1. Add the protocol shape to the fixture file it belongs in. If it comes from a
   consumer, say which one in a comment — a fixture nobody has in production is
   a shape nobody has to support.
2. Run `./run-checks.sh --record` and **read the snapshot diff**. That diff is
   the review: it is the only place the generated output is visible.
3. Add a behaviour check if the shape has runtime semantics (a stream to drive,
   a suspension to observe, a counter to assert).
