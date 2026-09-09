# Contributing

How the templates are built, where to change what, and which traps have already been hit.

For **what the templates generate** and how to consume them, see [README.md](README.md). For **what
changed in each release**, see [CHANGELOG.md](CHANGELOG.md).

## Repository layout

```
templates/                          # the product
  Mocks.swifttemplate               # entry point — includes Mocks/*, filters by `CreateMock`
  TypeErase.swifttemplate           # entry point for type erasure
  Component.swifttemplate           # entry point — the same includes plus Component/, filters by `DuetComponent`
  _header.swifttemplate             # shared header — imports, SwiftLint directives
  Mocks/
    MockGenerator.swift             # orchestrator: iterates protocols, emits class shells
    MockMethod.swift                # method mocking: signature, handler closure, call count
    MockVar.swift                   # variable mocking: get/set tracking, smart defaults
    SourceCode.swift                # SourceCode + TopScope — indented output
    SourceryRuntimeExtensions.swift # default values, smart defaults, the concurrency helpers
  Component/
    ComponentGenerator.swift        # forwarding emission; consumes the Mocks/ rules
  Utility/                          # annotation parsing, generics, string helpers

Sources/mock-templates/             # the CLI: generate (wraps Sourcery), imprint, validate
  MockTemplates.swift               # command tree
  Commands.swift                    # the three verbs + their shared options
  Fingerprint.swift                 # the provenance block — format, render, parse
  SourceSet.swift                   # input enumeration and root-relative paths

Plugins/SourcerySwiftCodegenPlugin/ # SPM prebuild plugin
Checks/                             # fast lane + CLI lane — see Testing below
Scripts/assemble-release.sh         # builds the release assets — see Cutting a release
Examples/ExampleProjectSpm/         # full lane — RxSwift, RIBs, type erasure, the plugin
Examples/ExampleProjectCocoapods/   # stale; see Open items
```

An `includeFile` in a `.swifttemplate` inlines that file into one compilation unit, so `private` at
file scope is visible across every included file. That is why `Component/ComponentGenerator.swift` can
call `MethodParameter.parametersDecl`, declared `private` in `Mocks/MockMethod.swift`.

## How generation works

```
Protocol source files
  ↓ Sourcery parses
SourceryRuntime type graph (Type, Method, MethodParameter, TypeName)
  ↓ the template filters by annotation
Mocks.swifttemplate     → MockGenerator.generate()      → MockVar.from / MockMethod.from
Component.swifttemplate → ComponentGenerator.generate()
  ↓
SourceCode / TopScope → indented Swift source
```

`MockMethod.mockImpl()` emits, per protocol method: the signature, `<name>CallCount += 1`,
`<name>Args.append(…)` where the method records anything, the
`if let __handler = self.<name>Handler` call, then a fallback (smart default, `nil`, or `fatalError`).
Recording precedes the handler so that a handler which throws still leaves the call recorded.
`ComponentGenerator.forwarder(for:access:isolated:)` emits, per requirement, a single forwarding
member — one overload for variables, one for methods.

**The SPM plugin** (`SourcerySwiftCodegenPlugin.swift`) runs as a prebuild command: locates the
Sourcery binary in the artifact bundle, discovers `*.sourcery.yml` files in the target's sources,
exports `SOURCERY_TARGET_*` environment variables for target and dependency source paths, and runs
Sourcery per config. Output lands in `$SOURCERY_OUTPUT_DIR` inside DerivedData, never in the source
tree — which is why `Checks/Snapshots/` exists at all.

`modaal-firebase-wrappers` uses the other mode: `sourcery` invoked from a script, output committed, so
its consumers need no Sourcery installation.

## Where to change what

### A new type attribute (the `@escaping` / `@Sendable` shape)

1. Find the key in `SourceryRuntime.TypeName.attributes`
2. Add it to `MethodParameter.closureAttributesDecl` in `Mocks/MockMethod.swift` — the **one** place
   that decides which attributes survive. Both the signature and the handler type read it, and the
   Component forwarder reads it through `parametersDecl`
3. Add the shape to `Checks/Fixtures/`, `--record`, read the diff
4. If it needs RxSwift or RIBs to express, add a protocol to the example project's `Protocols.swift`
   and a Quick spec

### A new smart default value

1. `Mocks/SourceryRuntimeExtensions.swift` — `defaultValue()` for plain types
2. `smartDefaultValueImplementation()` and `hasComplexTypeWithSmartDefaultValue()` for complex ones
   (RxSwift, Combine)
3. **Mind the match order**: `AnyPublisher`, then `AnyCancellable`, then `Disposable`, then the
   RxSwift generics. A case inserted in the wrong place silently changes which branch an existing type
   takes; the snapshot gate is what surfaces it
4. Add the shape to `Checks/Fixtures/`, `--record`, read the diff

### A concurrency rule

1. `Mocks/SourceryRuntimeExtensions.swift` — the `// MARK: - Concurrency` block holds the detection:
   `globalActorAttributeName`, `requiresUncheckedSendable`, `isDeclaredNonisolated`,
   `emitsNonisolatedMembers`
2. `MockGenerator.swift` for anything on the class declaration; `MockMethod.swift` / `MockVar.swift`
   for anything on a member. Member modifiers go through `isolationDecl` (the declaration) and
   `storageIsolationDecl` (its backing storage) — the two are different and both are needed
3. `Component/ComponentGenerator.swift` reads the same helpers. Add the rule once, in the helper, not
   twice at the two call sites
4. Verify under **both** language modes: a construct can be a warning under Swift 5 with complete
   checking and an error under Swift 6

### What a Component forwards

1. `Component/ComponentGenerator.swift` — `forwarder(for:access:isolated:)` per member kind;
   `reject(unsupportedMembersOf:)` holds the refusals
2. Reuse rather than restate: isolation from `Mocks/SourceryRuntimeExtensions.swift`, parameter
   declarations from `MethodParameter.parametersDecl`
3. Add the requirement shape to `Checks/Fixtures/Forwarding.swift`, `--record`, read the diff, and add
   a behaviour assertion — forwarding has runtime semantics (identity, mutation reaching the parent,
   `inout` by reference) that a typecheck does not see
4. A construct that cannot be forwarded belongs in `reject(...)` with a sentence naming what the
   author should do, not in a partial emission

### A new annotation

1. `Utility/Annotations.swift` — parsing
2. `Mocks/MockVar.swift` / `Mocks/MockMethod.swift`, or `Component/ComponentGenerator.swift`
3. Add the row to README.md's annotations table

### The SPM plugin

1. `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`
2. Conditional compilation for the Swift 5.x vs 6.0+ plugin API differences
3. Test by building the example project — the fast lane does not exercise the plugin

### The `mock-templates` CLI

1. `Sources/mock-templates/` — the fingerprint block format lives in `Fingerprint.swift`, the
   input-enumeration rule in `SourceSet.swift` (every regular `.swift` file under a root, hidden
   entries skipped, recorded root-relative, sorted), the verbs in `Commands.swift`
2. The CLI is policy-free: it hashes what it is pointed at and knows nothing about who calls it.
   Anything that decides *which* sources, templates or tag — keep in the calling script
3. Run `Checks/run-cli-checks.sh`. Its transparency gate diffs `generate`'s body against the fast
   lane's snapshot, so a wrapper change that alters output is caught even when the templates never
   changed
4. A block-format change invalidates every committed fingerprint downstream — bump the version in
   the header line (`mock-templates:fingerprint v1`) and say so in CHANGELOG.md

## Design rules already decided

**Mock classes are `final`.** Subclassing a generated mock is not supported; setting a handler is the
supported way to change behaviour.

**Member-level global actors are not propagated.** A non-isolated protocol whose method is
`@MainActor` produces a non-isolated mock method. A non-isolated witness satisfies the requirement,
and propagating would make the mock uncallable from a non-isolated test body.
`Checks/Fixtures/Isolation.swift`'s `TimelineBuildable` keeps this true.

**`owns` exists because a generated type cannot carry a hand-written `lazy var`**, and Swift has no
stored properties in extensions. The base-class split is the only shape that lets a composition level
own something. A wrong annotation is a compile error, not a silent defect.

**A generated Component is internal by default, even for a `public` protocol.** Deriving access from
the protocol would widen a module's API surface as a side effect of generating boilerplate;
`componentAccess = "public"` is the opt-in.

**Arguments are recorded by default, and closures never are.** `<method>Args` is generated for every
mocked method with at least one non-closure parameter: an annotation per method would make the common
case the opt-in one. Closures are excluded on two counts — a non-escaping one cannot be stored at
all, and storing an escaping one keeps the caller's captures alive for as long as the mock, which a
consumer's leak or churn spec reads as a retain by the code under test. The same hazard exists for a
value parameter of reference type, and `skipArgumentRecording` — on the method or on the protocol —
is its escape hatch; `Checks/Behaviour/Main.swift`'s `checkArgumentRecordingOptOut` asserts both
halves with a `weak var`. A generic method records nothing: its parameter types name the *method's*
generic parameters and a stored property can only name the class's, so the array would be typed
against a different `S` than the call has.

**An `AnyPublisher` member is backed by a `PassthroughSubject` — variable and method alike — and a
replaying stream is the test's to supply through the member's closure.** This is the rule the
RxSwift branch has always applied with `PublishSubject`, and the Combine branch now matches it
rather than running a second policy. A seeded `CurrentValueSubject` makes the double emit a value no
test wrote — `""`, `[:]`, `[]` — the moment the code under test subscribes; the test's own `send` is
then a *second* element, and a bridge awaiting the first value resumes its continuation twice and
traps. It cannot be opted out of at the call site either: assigning a `PassthroughSubject` to a
`CurrentValueSubject`-typed property does not compile. Replay goes through `<name>GetHandler` /
`<name>Handler`, which every publisher member already generates, or through
`/// sourcery: subject = "CurrentValue"` when every test for that member wants it.
`Checks/Behaviour/Main.swift`'s `checkCombineStreams` asserts all four corners: the default does not
replay, a get handler that returns a `CurrentValueSubject` does, `share(id:)` says nothing until the
test sends, and the annotated `token()` answers on subscribe.

**A Component refuses what it cannot forward** — `static`, `init` and `subscript` requirements, and
associated types — with a diagnostic naming the member. Check `isInitializer` **before** `isStatic`:
Sourcery reports an initializer requirement as static too, and the wrong branch produces a sentence
that does not tell the author what to do.

## Pitfalls

- **`typeName.name` vs `typeName.asSource`.** `.name` strips type attributes (`@escaping`,
  `@Sendable`); `.asSource` carries all of them, including `@autoclosure`, which is legal on a
  function parameter but not on a closure type parameter. Neither is usable wholesale — each
  attribute is opted into explicitly in `closureAttributesDecl`.
- **Handler closure parameters keep `@escaping`.** Without it the handler implementation cannot
  capture the closure and dispatch it later, which is the case a snapshot-listener test needs.
- **Overload disambiguation is deterministic.** Overloaded methods fall back to long-form names
  (including parameter labels). If those still collide — same name *and* parameter list, differing
  only by return type, as when a refining protocol overrides `func data() -> [String: Any]?` with
  `func data() -> [String: Any]` — a sanitized return-type suffix is appended
  (`dataStringAnyOptionalHandler` vs `dataStringAnyHandler`). Optional types contribute an `Optional`
  suffix; bracket, colon and space characters are stripped and the remainder camel-cased.
  `ReturnTypeOverloadMocksSpec.swift` is the reproducer, mirroring Firebase's
  `QueryDocumentSnapshot : DocumentSnapshot`.
- **A non-Sendable mock and `async`.** A mock of a non-isolated protocol is a non-Sendable class.
  Constructing it on the main actor and then calling a nonisolated `async` member sends it across an
  isolation boundary, which Swift 6 rejects — the test body has to be non-isolated too. This is
  Swift's rule, not a template defect; `Checks/Behaviour/Main.swift`'s `checkAsync` documents it in
  place.
- **`SourceryRuntime.Protocol` needs backticks** inside a template: the unquoted form collides with
  Foundation's Objective-C protocol metatype and fails to resolve.
- **Never emit `typeName.name` or `typeName.asSource` directly** — emit `typeName.declaredName`, or
  `mockTypeName` where a smart default is also in play. The parser returns `(any Sheet)?` as
  `any Sheet?` in both properties, and that does not compile: *"optional 'any' type must be written
  '(any Sheet)?'"*. The loss is the same for `some`, for compositions (`(any A & B)?`), and for the
  type nested inside a closure parameter — which is why
  `TypeName.parenthesizingOptionalExistentials` works on the rendered string rather than branching on
  `isOptional`. `DetailPresenting` in `Checks/Fixtures/Composition.swift` pins all four positions.
- **Sourcery only knows the declarations it parses.** `allVariables` / `allMethods` include an
  inherited requirement only when the inherited protocol is among the `--sources`. A protocol
  refining one from *another module* generates a mock missing those requirements, and the failure
  surfaces in the consumer's build as "type 'XMock' does not conform to protocol 'Y'" — never here.
  The fix belongs to whatever drives generation: pass the other module's sources too. The Duet
  reference app's `scripts/generate-mocks.sh` derives them from `swift package dump-package` (every
  path dependency, plus the framework at its exact pin) rather than listing paths, so a new
  refinement across a first-party module boundary needs no change to the script.

### SourceryRuntime API notes

`MethodParameter`: `name` (internal name), `argumentLabel` (nil means `_`), `typeName.name`,
`typeName.asSource`, `typeName.attributes` (`[String: [Attribute]]`), `typeName.isClosure`, `inout`.
This repo adds `isRecordable` (whether `<method>Args` carries it) and `recordedTypeName` (the element
type it contributes — `declaredName` with `inout` dropped).

`TypeName`: `name`, `asSource`, `isOptional` / `isVoid` / `isArray` / `isDictionary` / `isTuple` /
`isClosure`, `unwrappedTypeName`, `attributes`, `generic`. This repo adds `declaredName` (what to
emit) and `mockTypeName` (what to emit for a mocked member, smart defaults included).

`Type`: `allVariables` / `allMethods` include inherited requirements — that is what makes a refining
protocol work. `Variable.isAsync` and `Variable.throws` carry effectful property requirements.

## Testing

| lane | command | needs |
|------|---------|-------|
| fast | `Checks/run-checks.sh` | a Swift toolchain; ~10s |
| CLI | `Checks/run-cli-checks.sh` | a Swift toolchain; ~30s cold, seconds warm |
| full | `cd Examples/ExampleProjectSpm && ./test-ios.sh` | an iOS Simulator; minutes |

Both check lanes provision the pinned Sourcery through `Checks/ensure-sourcery.sh` — the pin and the
download path live once; `SOURCERY=/path/to/sourcery` overrides it in either lane.

The fast lane runs every template in its `TEMPLATES` list over `Checks/Fixtures`, diffs each output
against `Checks/Snapshots/`, typechecks the fixtures **and all generated files together** under
`-swift-version 5 -strict-concurrency=complete` and `-swift-version 6` at zero diagnostics, then runs
`Checks/Behaviour/Main.swift` — plain assertions in one executable, no test framework. Compiling every
template's output in one invocation is what keeps a mock and a Component of the same protocol from
disagreeing about isolation.

Adding a template is one line in `TEMPLATES` plus a recorded snapshot.

The full lane is Quick + Nimble specs in `Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/`,
driven by the prebuild plugin. It covers what the fast lane structurally cannot: RxSwift smart
defaults, the RIBs external-annotation pattern, type erasure, and the plugin itself.

`test-ios.sh` resolves whatever iOS runtime is installed; override with `DESTINATION`, `OS_VERSION` or
`DEVICE_NAME`.

### What each artifact covers

| lane | file | covers |
|------|------|--------|
| fast | `Checks/Snapshots/Mocks.generated.swift` | the generated mocks, as a reviewable diff |
| fast | `Checks/Snapshots/Components.generated.swift` | the generated Components, as a reviewable diff |
| fast | `Checks/Behaviour/Main.swift` | call counting, handlers, async suspension, nonisolated access off the main actor, subject-driven streams, cancellation counting, composites; for Components: forwarding identity, per-Component ownership, settable forwarding, parameter shapes, effectful getters |
| CLI | `Checks/run-cli-checks.sh` | `generate` transparency against the fast lane's snapshot; determinism across runs; `validate` red on a mutated input, an unlisted file, a hand-edited body, a wrong bundle tag, a `--template`/`--args` pair the block does not record; `imprint` recovery |
| full | `SwiftSourceryTemplatesMocksSpec.swift` | mock instantiation, call counting, handler execution |
| full | `EscapingClosureMocksSpec.swift` | `@escaping` preservation — capture, async dispatch |
| full | `ReturnTypeOverloadMocksSpec.swift` | return-type-only overload disambiguation |
| full | `SwiftSourceryTemplatesTypeErasureSpec.swift` | type erasure wrapper conformance |

`Checks/README.md` maps construct → fixture.

### CI

`.github/workflows/ci.yml` runs all three lanes on every push: fast and CLI in parallel, full gated
on fast. Xcode is
pinned via `XCODE_VERSION` because the fast lane's gate is *zero diagnostics*: a runner image whose
compiler emits one new warning would turn it red for a reason unrelated to the templates. The gate has
been measured to hold on Swift 6.3.3 (Xcode 26.6) and Swift 6.4 (Xcode 27 beta 4), so the pin is for
reproducibility rather than fragility. Bumping it means re-running the lanes locally on the new
version first.

`.github/workflows/release.yml` runs on tag pushes only (which ci.yml deliberately skips): it runs
`Scripts/assemble-release.sh` and attaches the assets it produces to the tag's GitHub release.

## Cutting a release

1. Run all three lanes green
2. Regenerate the reference consumer (`modaal-firebase-wrappers`) against `master` and record the size
   and shape of its diff. A release whose consumer impact was not measured is not ready to tag
3. Write the `CHANGELOG.md` entry **before** tagging. It is written for a consumer deciding whether to
   bump: what the generated output looks like now, what can fail after a regenerate and how to fix it,
   what to do beyond bumping the tag
4. Tag `master`. There is no release branch, and a tag does not publish a pod
5. The tag push runs `.github/workflows/release.yml`, which publishes the release assets:
   `Scripts/assemble-release.sh <tag>` builds the `mock-templates` CLI universal
   (arm64 + x86_64), vendors the Sourcery engine at the `sourcery` binaryTarget pin in
   `Package.swift` (the manifest is the only pin; the download is checksum-verified against it),
   smoke-runs `generate` + `validate` from the assembled layout, and emits
   `swift-sourcery-templates-<tag>.artifactbundle.zip`, `mock-templates-<tag>-macos.zip`, a
   `.sha256` beside each, and the release-notes body. Rehearse it locally with
   `Scripts/assemble-release.sh <version>` — everything lands in `.build/release-assets/`

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Sourcery | 2.3.0 | code generation engine (binary artifact); the pin of record is the `sourcery` binaryTarget in `Package.swift` — `Scripts/assemble-release.sh` parses it when vendoring the engine into the release bundle; `Checks/ensure-sourcery.sh` keeps a copy for the check lanes |
| swift-argument-parser | 1.3.0+ | the `mock-templates` CLI's command-line surface |
| Quick | 7.3.0 | BDD test framework (full lane) |
| Nimble | 13.0.0 | matchers (full lane) |
| RxSwift | 6.6.0 | example protocols, smart defaults |
| RIBs | 0.16.1 | example protocols, external annotation pattern |
| Alamofire | 4.9.1 | example dependency |

## Consumers

- **[modaal-firebase-wrappers](https://github.com/modaal-agent/modaal-firebase-wrappers)** — the
  reference consumer: 34 mocks across 7 modules, pre-generated and committed. Its
  `scripts/generate-mocks.sh` is the adopter pattern worth copying — templates cloned at a pinned tag,
  annotations in their own directory, one output file per module, `TEMPLATES_DIR` override for local
  iteration. Regenerate it when measuring a release's consumer impact.
- **The Duet reference app** — drove 0.2.15 and the Component template. 93
  `/// sourcery: CreateMock` annotations including an `<X>Dependency` protocol at each of its 13
  composition levels, built with `-strict-concurrency=complete`; the `Checks/Fixtures/` shapes are
  taken from it. The shape the Component template emits is specified in `modaal-agent`'s
  `specs/100-android-parity/27-duet-composition-shape.md` — §2 for the rule, §13 for the
  macro-vs-template measurement behind choosing a template.

## Open items

- **`public` access modifier on generated mocks.** Mock classes and their members are `internal`, so
  a consumer shipping mocks in a separate SPM product needs `@testable import`. Making them `public`
  touches `MockGenerator.swift` (class declaration, initializer), `MockMethod.swift` (func,
  `<name>CallCount`, `<name>Handler`) and `MockVar.swift` (the variable, `GetCount` / `GetHandler` /
  `SetCount`). Decide whether it is the default or gated behind an annotation
  (`sourcery: publicMock`) or a template arg (`--args publicMocks`); `public` as the default is
  probably right, since mocks are always consumed from another module.
- **Effectful property requirements in the mock template.** `var x: T { get async throws }` is parsed
  by Sourcery (`Variable.isAsync`, `Variable.throws`) and ignored by `Mocks.swifttemplate`, which
  emits a plain property that does not satisfy the requirement. Fixing it means always emitting a
  computed property with a `get async throws { }` accessor plus a separate backing store — a new
  naming convention, so it was left out of 0.2.15 rather than guessed at. No consumer uses the shape.
  The Component template **does** forward it (`Checks/Fixtures/Forwarding.swift`,
  `ProfileDependency`), because forwarding an effectful requirement is a pass-through and mocking one
  is not.
- **CocoaPods distribution is being retired.** `SwiftMockTemplates.podspec` (version `0.2.7`, Sourcery
  dependency `2.1.2`) and `Examples/ExampleProjectCocoapods` are stale against the SPM path and are
  not kept in step. Do not spend effort on them.
