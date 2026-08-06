# Checks — the fast lane

`./run-checks.sh` generates mocks from [`Fixtures/`](Fixtures) and holds the
result to three gates. It needs no simulator and no third-party package, so it
runs in a few seconds and is the loop to use while editing `templates/`.

```bash
Checks/run-checks.sh              # run the gates
Checks/run-checks.sh --record     # rewrite the snapshot, then run the gates
SOURCERY=/path/to/sourcery Checks/run-checks.sh
```

| gate | what it proves |
| --- | --- |
| **snapshot** | the generated file matches [`Snapshots/Mocks.generated.swift`](Snapshots/Mocks.generated.swift), so every template change shows up as a reviewable diff of real output |
| **typecheck** | it compiles with **zero diagnostics** under `-swift-version 5 -strict-concurrency=complete` **and** under `-swift-version 6` |
| **behaviour** | the mock counts calls, runs handlers, suspends where the protocol suspends, and delivers values pushed into its subjects — [`Behaviour/Main.swift`](Behaviour/Main.swift), plain assertions in one executable |

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
