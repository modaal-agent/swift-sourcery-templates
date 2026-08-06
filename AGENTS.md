# Agent Handoff Guide

This document captures working context for AI agents continuing work on this project.

## Current State (2026-08-06)

**Latest tag:** 0.2.15 — the concurrency + Combine work below, and the `Checks/` lane.

**Cutting a release:** run both lanes green, write the `CHANGELOG.md` entry *before* tagging (it is
written for a consumer deciding whether to bump — generated-output diff, what breaks, what to do),
then tag `master`. Regenerate the reference consumer and record the size and shape of its diff in the
entry; a release whose consumer impact was not measured is not ready to tag.

### Current work: mocks that compile under strict concurrency (unreleased)

**Problem.** A consumer building with `-strict-concurrency=complete` could not use generated mocks
for the shapes it actually has. Four gaps, all in the template rather than in Sourcery — Sourcery
parses every one of these constructs correctly:

| gap | before | after |
|---|---|---|
| `async` dropped from the signature | `func run() async` → `func run()`; compiles (Swift allows a less-effectful witness) but the mock can never suspend | ` async` in the signature and the handler type, `await` at the handler call |
| isolation dropped | a `nonisolated` requirement on a `@MainActor` protocol emitted a plain member on a class that inferred isolation → **build failure** | the global actor is declared on the class; `nonisolated` on the member; `nonisolated(unsafe)` on its counter and handler |
| Combine had no smart default | `AnyPublisher` became a stored property with a mandatory init parameter; only RxSwift was handled | a subject the test drives (`<name>Subject`), `CurrentValueSubject` or `PassthroughSubject` by element type |
| neither `final` nor `Sendable` | `class XMock: X` — a `Sendable` protocol's mock could not compile in Swift 6 | `final class XMock: X, @unchecked Sendable` when the protocol refines `Sendable` |

Plus two taken while the surrounding code was open:

- **`AnyCancellable` smart default.** A method returning `AnyCancellable` now gets a token whose
  `cancel()` is counted, mirroring the RxSwift `Disposable` case. Before, such a method trapped with
  `fatalError` unless every call site set a handler. The WikiMemory corpus has 12 of them.
- **`@Sendable` closure parameters** are preserved alongside `@escaping`, through a shared
  `MethodParameter.closureAttributesDecl`. Measured consequence of dropping it: conformance holds
  either way (a witness taking a non-Sendable closure is the more general one) and capturing the
  closure works, but handing the captured closure to anything `@Sendable`-constrained fails —
  *"converting non-Sendable function value to '@Sendable (Bool) -> Void' may introduce data races"*.
  No consumer declares such a requirement today; it was closed because the fix is two lines in code
  that was already open, and the alternative is a future consumer needing a template release.

**Files changed:** `MockGenerator.swift` (class declaration), `MockMethod.swift` (async + isolation
modifiers), `MockVar.swift` (isolation modifiers, subject kind), `SourceryRuntimeExtensions.swift`
(the concurrency helpers, `AnyPublisher` and `AnyCancellable` smart defaults), `SourceCode.swift`
(`prefixed(_:)`).

**Consumer impact.** `modaal-firebase-wrappers` regenerates with a diff of exactly 34 lines —
`class XMock` → `final class XMock`, nothing else. Its `scripts/generate-mocks.sh` counts mocks with
`grep -c "^class .*Mock"`, which no longer matches; the count prints `0` until that grep is updated
(cosmetic — generation itself is unaffected). Copy the script's *pattern*, not that line.

**Behaviour changes to be aware of when bumping a consumer:**
- mock classes are now `final` — subclassing a generated mock no longer compiles;
- a `@MainActor` protocol's mock is now explicitly `@MainActor`, so constructing it from a
  non-isolated context needs the usual isolation hop;
- an `AnyPublisher` member that used to be an init parameter is now subject-backed, which **removes**
  it from the initializer.

### Testing setup added with it

`Checks/run-checks.sh` — generate from `Checks/Fixtures`, then: snapshot diff against
`Checks/Snapshots/Mocks.generated.swift`, typecheck under `-swift-version 5
-strict-concurrency=complete` and `-swift-version 6` (zero diagnostics, not just zero errors), and a
behaviour executable with 24 runtime assertions. No simulator, no third-party packages.

The snapshot is the part worth keeping: before it, generated output existed only in DerivedData, so
a template change was reviewable only through its effect on a test. Now it is a diff.

The fixtures are protocol shapes taken from the WikiMemory reference app — a `<X>Dependency` per
composition level, `@MainActor` repositories, a `nonisolated` subtree port, `async` staging seams,
`AnyPublisher` state streams, `AnyCancellable` registrations. `Checks/README.md` maps construct →
fixture.

### Previous Fix: @escaping Preservation

**Problem:** Generated mock methods stripped `@escaping` from closure parameters. The mock's method signature and handler closure type both used `typeName.name` which excludes type attributes. This meant:
- Mock methods didn't match the protocol's `@escaping` contract
- Handler implementations couldn't capture closure parameters for async dispatch
- Tests couldn't store listener callbacks for later invocation

**Fix:** Two changes in `templates/Mocks/MockMethod.swift`:
- `parametersDecl` (method signature): checks `typeName.isClosure && typeName.attributes["escaping"] != nil` and prepends `@escaping`
- `mockHandlerImpl` (handler closure type): same check, same fix

**Test coverage:** `EscapingClosureMocksSpec.swift` in the example project — 5 tests covering completion handler capture, listener capture, typealias'd closures, mixed escaping/non-escaping parameters.

**Consumer impact:** `modaal-firebase-wrappers` depends on these templates for mock generation. The fix unblocks Combine bridge tests where snapshot listener mocks need to capture and async-dispatch the listener closure.

## Architecture

### Template Execution Flow

```
Protocol source files
  ↓ (Sourcery parses)
SourceryRuntime type graph (Type, Method, MethodParameter, TypeName)
  ↓ (Template filters by annotation)
Mocks.swifttemplate → MockGenerator.generate()
  ↓
MockVar.from(type)     → variable mocking
MockMethod.from(type)  → method mocking
  ↓
SourceCode/TopScope    → indented Swift source output
```

### Mock Generation Pipeline (MockMethod)

```
Protocol method → MockMethod instance
  ↓
mockImpl() generates:
  1. Method signature:  func name(params) throws -> ReturnType
  2. Call count:        methodNameCallCount += 1
  3. Handler call:      if let handler = methodNameHandler { handler(params) }
  4. Fallback:          return default / fatalError / nil
  ↓
mockHandlerImpl generates:
  var methodNameHandler: ((params) throws -> (ReturnType))? = nil
  var methodNameCallCount: Int = 0
```

### SPM Plugin Architecture

`SourcerySwiftCodegenPlugin.swift` runs as a prebuild command:
1. Locates Sourcery 2.3.0 binary from artifact bundle
2. Discovers all `.sourcery.yml` config files in target source directories
3. Exports environment variables for target/dependency source paths
4. Runs Sourcery with each config file
5. Output goes to `$SOURCERY_OUTPUT_DIR` (in DerivedData, not source tree)

### Two Ways to Use the Templates

| Mode | How | When |
|------|-----|------|
| **SPM Plugin** | Add plugin to Package.swift, config via `.sourcery.yml` | In-project, mocks regenerate on every build |
| **CLI Script** | Run `sourcery` directly with `--sources`, `--templates`, `--output` | External projects, pre-generated committed mocks |

The `modaal-firebase-wrappers` repo uses CLI mode — mocks are generated locally and committed, so consumers don't need Sourcery installed.

## Key Files for Common Tasks

### Adding a new type attribute (like @escaping)

1. Check `SourceryRuntime.TypeName.attributes` for the attribute key
2. Update `MockMethod.swift`:
   - `parametersDecl` extension — method signature emission
   - `mockHandlerImpl` — handler closure type emission
3. Add test protocol in `Examples/ExampleProjectSpm/Sources/ExampleProjectSpm/Protocols/Protocols.swift`
4. Add test spec in `Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/`

### Adding a new smart default value

1. `templates/Mocks/SourceryRuntimeExtensions.swift` — `defaultValue()` method
2. For complex types (RxSwift, Combine): `smartDefaultValueImplementation()` and `hasComplexTypeWithSmartDefaultValue()`
3. Mind the match order — `AnyPublisher`, then `AnyCancellable`, then `Disposable`, then the RxSwift
   generics. A new case in the wrong place changes which branch an existing type takes; the snapshot
   gate in `Checks/` is what surfaces that.
4. Add the shape to `Checks/Fixtures/`, run `Checks/run-checks.sh --record`, and read the diff.

### Adding a concurrency rule

1. `SourceryRuntimeExtensions.swift` — the `// MARK: - Concurrency` block holds the detection
   (`globalActorAttributeName`, `requiresUncheckedSendable`, `isDeclaredNonisolated`,
   `emitsNonisolatedMembers`)
2. `MockGenerator.swift` for anything on the class declaration; `MockMethod.swift` / `MockVar.swift`
   for anything on a member. Member modifiers go through `isolationDecl` (declarations) and
   `storageIsolationDecl` (their backing storage) — the two are different and both are needed.
3. Verify against **both** language modes. A construct can be a warning under Swift 5 with complete
   checking and an error under Swift 6; the checks fail on either.

### Adding a new annotation

1. `templates/Utility/Annotations.swift` — parsing logic
2. `templates/Mocks/MockVar.swift` or `MockMethod.swift` — consuming the annotation
3. Update CLAUDE.md annotations table

### Modifying the SPM plugin

1. `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`
2. Conditional compilation for Swift 5.x vs 6.0+ API differences
3. Test by building the example project

## Testing

### Two lanes

| lane | command | needs |
|------|---------|-------|
| fast | `Checks/run-checks.sh` | nothing but a Swift toolchain; ~10s |
| full | `cd Examples/ExampleProjectSpm && ./test-ios.sh` | an iOS Simulator; minutes |

Both run in CI on every push (`.github/workflows/ci.yml`), fast lane first, full lane gated on it.
Xcode is pinned there via `XCODE_VERSION`: the fast lane's gate is *zero diagnostics*, so a runner
image that ships a compiler emitting one new warning would turn it red for a reason unrelated to the
templates. Bumping the pin is a deliberate change — re-run both lanes locally on the new version
first. The gate has been measured to hold on Swift 6.3.3 (Xcode 26.6) and Swift 6.4 (Xcode 27 beta 4).

The fast lane has no test framework: assertions live in `Checks/Behaviour/Main.swift`, compiled into
one executable. The full lane is Quick + Nimble specs in
`Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/`, driven by the prebuild plugin.

`test-ios.sh` resolves whatever iOS runtime is installed; override with `DESTINATION`, `OS_VERSION`
or `DEVICE_NAME`. It previously pinned an OS version, which aged out of the machine.

### Test Structure

| Lane | File | What it tests |
|------|------|---------------|
| fast | `Checks/Snapshots/Mocks.generated.swift` | the generated output itself, as a reviewable diff |
| fast | `Checks/run-checks.sh` typecheck | zero diagnostics under Swift 5 + complete concurrency, and under Swift 6 |
| fast | `Checks/Behaviour/Main.swift` | call counting, handlers, async suspension, nonisolated access off the main actor, subject-driven streams, cancellation counting, composite protocols |
| full | `SwiftSourceryTemplatesMocksSpec.swift` | Basic mock instantiation, call counting, handler execution |
| full | `EscapingClosureMocksSpec.swift` | @escaping attribute preservation (capture, async dispatch) |
| full | `ReturnTypeOverloadMocksSpec.swift` | return-type-only overload disambiguation |
| full | `SwiftSourceryTemplatesTypeErasureSpec.swift` | Type erasure wrapper conformance |

### Adding Tests for Template Changes

For anything a plain macOS compile can express — which is most of it — use the fast lane:

1. Add the protocol shape to `Checks/Fixtures/`, naming the consumer it came from
2. `Checks/run-checks.sh --record`, then **read the snapshot diff** before committing it
3. Add a behaviour assertion if the shape has runtime semantics (a stream to drive, a suspension to
   observe, a counter to assert)

Use the example project when the shape needs RxSwift, RIBs, type erasure or the SPM plugin:

1. Add a protocol with the relevant pattern to `Protocols.swift`
2. Add a Quick spec verifying the generated mock compiles and behaves correctly
3. Run `./test-ios.sh` — the plugin regenerates mocks before building tests

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Sourcery | 2.3.0 | Code generation engine (binary artifact) |
| Quick | 7.3.0 | BDD test framework |
| Nimble | 13.0.0 | Matcher library for Quick |
| RxSwift | 6.6.0 | Example protocols, smart defaults |
| RIBs | 0.16.1 | Example protocols, external annotation pattern |
| Alamofire | 4.9.1 | Example dependency for testing |

## Related Projects

- **[modaal-firebase-wrappers](https://github.com/modaal-agent/modaal-firebase-wrappers)** — Primary consumer. Uses CLI mode to pre-generate mocks for 34 Firebase protocol wrappers. Templates pinned to tag `0.2.14`. The `@escaping` fix was driven by this project's need to test Combine streaming publishers with mock snapshot listeners. `scripts/generate-mocks.sh` there is the adopter pattern worth copying: templates cloned at a pinned tag, annotations in their own directory, one output file per module, `TEMPLATES_DIR` override for local iteration.

- **WikiMemory (Duet reference app)** — the consumer that drove 0.2.15. It carries 93 `/// sourcery: CreateMock` annotations, including a `<X>Dependency` protocol at each of its 13 composition levels, and builds with `-strict-concurrency=complete`; the `Checks/Fixtures/` shapes are taken from it. The design it encodes is specified in `modaal-agent`'s `specs/100-android-parity/27-duet-composition-shape.md`.

- **[modaal-agent](https://github.com/modaal-agent/modaal-agent)** — Parent project. Specs at `specs/066-integrations-firebase/firebase-shared-wrapper-followup-plan.md` document the mock generation setup.

## Open Items

- **`public` access modifier on generated mocks (next priority):** Mock classes are `internal` (no access modifier). Consumers must use `@testable import` to access them. Mocks should be `public` so they're usable with a plain `import`. Files to change:

  | File | What to prefix with `public` |
  |------|------------------------------|
  | `MockGenerator.swift:29` | `class <Name>Mock` → `public class <Name>Mock` |
  | `MockGenerator.swift:49` | `init(...)` → `public init(...)` |
  | `MockMethod.swift:72` | `func <name>(...)` → `public func <name>(...)` |
  | `MockMethod.swift:115` | `var <name>CallCount` → `public var <name>CallCount` |
  | `MockMethod.swift:131` | `var <name>Handler` → `public var <name>Handler` |
  | `MockVar.swift:38,60,64` | `var <name>: <Type>` → `public var <name>: <Type>` |
  | `MockVar.swift:45-46,66-67,79` | `var <name>GetCount/GetHandler/SetCount` → `public var ...` |

  Consider gating behind an annotation (`sourcery: publicMock`) or template arg (`--args publicMocks`) for backward compatibility, though making `public` the default is likely the right call since mocks are always consumed from a separate module.

- **Effectful property requirements:** `var x: T { get async throws }` is parsed by Sourcery
  (`Variable.isAsync`, `Variable.throws`) and ignored by the template, which emits a plain stored or
  computed property. That does not satisfy the requirement. Fixing it means the mock always emits a
  computed property with a `get async throws { }` accessor and a separate backing store — a new
  naming convention, so it was left out of 0.2.15 rather than guessed at. No consumer uses the shape
  today.
- **CocoaPods distribution is being retired.** `SwiftMockTemplates.podspec` (version `0.2.7`, Sourcery
  dependency `2.1.2`) and `Examples/ExampleProjectCocoapods` are both stale against the SPM path and
  are not being kept in step. Do not spend effort on them; a tag does not publish a pod.
