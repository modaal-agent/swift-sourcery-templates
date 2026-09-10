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

Plugins/SourcerySwiftCodegenPlugin/ # SPM prebuild plugin — one file, no dependencies allowed
Tests/                              # everything that verifies the product — see Testing below
  Checks/                           # fast lane + CLI lane + plugin lane + Xcode lane
    PluginFixture/                  # the plugin lane's green package: one target per config shape
    PluginFixtureRed/               # four packages that must FAIL, one per red control
    XcodeFixture/                   # the Xcode lane's green project — an xcodegen.yml, no .xcodeproj
    XcodeFixtureRed/                # one project per red control — each must FAIL
  Examples/ExampleProjectSpm/       # full lane — RxSwift, RIBs, type erasure, the plugin
Scripts/
  assemble-release.sh               # builds the release assets — see Cutting a release
  engine-pin.sh                     # the upstream Sourcery pin: version, zip, SHA-256
specs/                              # design specs, NNN-slug/spec.md — see What goes in which document
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
tree — which is why `Tests/Checks/Snapshots/` exists at all.

`modaal-firebase-wrappers` uses the other mode: `sourcery` invoked from a script, output committed, so
its consumers need no Sourcery installation.

## Where to change what

### A new type attribute (the `@escaping` / `@Sendable` shape)

1. Find the key in `SourceryRuntime.TypeName.attributes`
2. Add it to `MethodParameter.closureAttributesDecl` in `Mocks/MockMethod.swift` — the **one** place
   that decides which attributes survive. Both the signature and the handler type read it, and the
   Component forwarder reads it through `parametersDecl`
3. Add the shape to `Tests/Checks/Fixtures/`, `--record`, read the diff
4. If it needs RxSwift or RIBs to express, add a protocol to the example project's `Protocols.swift`
   and a Quick spec

### A new smart default value

1. `Mocks/SourceryRuntimeExtensions.swift` — `defaultValue()` for plain types
2. `smartDefaultValueImplementation()` and `hasComplexTypeWithSmartDefaultValue()` for complex ones
   (RxSwift, Combine)
3. **Mind the match order**: `AnyPublisher`, then `AnyCancellable`, then `Disposable`, then the
   RxSwift generics. A case inserted in the wrong place silently changes which branch an existing
   type takes; the snapshot gate is what surfaces it
4. Add the shape to `Tests/Checks/Fixtures/`, `--record`, read the diff

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
3. Add the requirement shape to `Tests/Checks/Fixtures/Forwarding.swift`, `--record`, read the diff,
   and add a behaviour assertion — forwarding has runtime semantics (identity, mutation reaching the
   parent, `inout` by reference) that a typecheck does not see
4. A construct that cannot be forwarded belongs in `reject(...)` with a sentence naming what the
   author should do, not in a partial emission

### A new annotation

1. `Utility/Annotations.swift` — parsing
2. `Mocks/MockVar.swift` / `Mocks/MockMethod.swift`, or `Component/ComponentGenerator.swift`
3. Add the row to README.md's annotations table

### The SPM plugin

1. `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift` — all of it. A build-tool
   plugin **cannot depend on a library target** (SwiftPM rejects it outright), so there is no Yams,
   no code shared with `Sources/mock-templates`, and no test target that can import any of these
   types. Everything is PackagePlugin + Foundation in one file
2. Three parts, in reading order: `YamlLine` (the line rules), `SourceryConfigSynthesizer` (the
   rewrite — placeholder, template names, defaults, the `output:` check), and `_createBuildCommands`
   (discovery, the per-config output directories, the collision check)
3. The synthesizer never parses YAML. It recognises a mapping key at column 0 and a whole list item,
   and copies every other byte through. A construct it does not recognise is one it does not touch —
   which is the whole safety argument, so keep new rules to that shape
4. Conditional compilation for the Swift 5.x vs 6.0+ plugin API differences
5. Run `Tests/Checks/run-plugin-checks.sh` — black-box over `Tests/Checks/PluginFixture`, ~1 minute,
   no simulator. It is the only lane that can test the plugin at all.
   `Tests/Examples/ExampleProjectSpm/test-ios.sh` covers it too, but through one package shape

### The `mock-templates` CLI

1. `Sources/mock-templates/` — the fingerprint block format lives in `Fingerprint.swift`, the
   input-enumeration rule in `SourceSet.swift` (every regular `.swift` file under a root, hidden
   entries skipped, recorded root-relative, sorted), the verbs in `Commands.swift`
2. The CLI is policy-free: it hashes what it is pointed at and knows nothing about who calls it.
   Anything that decides *which* sources, templates or tag — keep in the calling script
3. Run `Tests/Checks/run-cli-checks.sh`. Its transparency gate diffs `generate`'s body against the
   fast lane's snapshot, so a wrapper change that alters output is caught even when the templates
   never changed
4. A block-format change invalidates every committed fingerprint downstream — bump the version in
   the header line (`mock-templates:fingerprint v1`) and say so in CHANGELOG.md

## Design rules already decided

**Mock classes are `final`.** Subclassing a generated mock is not supported; setting a handler is the
supported way to change behaviour.

**Member-level global actors are not propagated.** A non-isolated protocol whose method is
`@MainActor` produces a non-isolated mock method. A non-isolated witness satisfies the requirement,
and propagating would make the mock uncallable from a non-isolated test body.
`Tests/Checks/Fixtures/Isolation.swift`'s `TimelineBuildable` keeps this true.

**`owns` exists because a generated type cannot carry a hand-written `lazy var`**, and Swift has no
stored properties in extensions. The base-class split is the only shape that lets a composition level
own something. A wrong annotation is a compile error, not a silent defect.

**A generated Component is internal by default, even for a `public` protocol.** Deriving access from
the protocol would widen a module's API surface as a side effect of generating boilerplate;
`componentAccess = "public"` is the opt-in.

**Arguments are recorded by default, and closures never are.** `<method>Args` is generated for every
mocked method with at least one non-closure parameter: an annotation per method would make the
common case the opt-in one. Closures are excluded on two counts — a non-escaping one cannot be
stored at all, and storing an escaping one keeps the caller's captures alive for as long as the
mock, which a consumer's leak or churn spec reads as a retain by the code under test. The same
hazard exists for a value parameter of reference type, and `skipArgumentRecording` — on the method
or on the protocol — is its escape hatch; `Tests/Checks/Behaviour/Main.swift`'s
`checkArgumentRecordingOptOut` asserts both halves with a `weak var`. A generic method records
nothing: its parameter types name the *method's* generic parameters and a stored property can only
name the class's, so the array would be typed against a different `S` than the call has.

**An `AnyPublisher` member is backed by a `PassthroughSubject` — variable and method alike — and a
replaying stream is the test's to supply through the member's closure.** This is the rule the
RxSwift branch has always applied with `PublishSubject`, and the Combine branch now matches it
rather than running a second policy. A seeded `CurrentValueSubject` makes the double emit a value no
test wrote — `""`, `[:]`, `[]` — the moment the code under test subscribes; the test's own `send` is
then a *second* element, and a bridge awaiting the first value resumes its continuation twice and
traps. It cannot be opted out of at the call site either: assigning a `PassthroughSubject` to a
`CurrentValueSubject`-typed property does not compile. Replay goes through `<name>GetHandler` /
`<name>Handler`, which every publisher member already generates, or through `/// sourcery: subject =
"CurrentValue"` when every test for that member wants it. `Tests/Checks/Behaviour/Main.swift`'s
`checkCombineStreams` asserts all four corners: the default does not replay, a get handler that
returns a `CurrentValueSubject` does, `share(id:)` says nothing until the test sends, and the
annotated `token()` answers on subscribe.

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
  (`dataStringAnyOptionalHandler` vs `dataStringAnyHandler`). Optional types contribute an
  `Optional` suffix; bracket, colon and space characters are stripped and the remainder camel-cased.
  `ReturnTypeOverloadMocksSpec.swift` is the reproducer, mirroring Firebase's `QueryDocumentSnapshot
  : DocumentSnapshot`.
- **A non-Sendable mock and `async`.** A mock of a non-isolated protocol is a non-Sendable class.
  Constructing it on the main actor and then calling a nonisolated `async` member sends it across an
  isolation boundary, which Swift 6 rejects — the test body has to be non-isolated too. This is
  Swift's rule, not a template defect; `Tests/Checks/Behaviour/Main.swift`'s `checkAsync` documents
  it in place.
- **`SourceryRuntime.Protocol` needs backticks** inside a template: the unquoted form collides with
  Foundation's Objective-C protocol metatype and fails to resolve.
- **Never emit `typeName.name` or `typeName.asSource` directly** — emit `typeName.declaredName`, or
  `mockTypeName` where a smart default is also in play. The parser returns `(any Sheet)?` as `any
  Sheet?` in both properties, and that does not compile: *"optional 'any' type must be written '(any
  Sheet)?'"*. The loss is the same for `some`, for compositions (`(any A & B)?`), and for the type
  nested inside a closure parameter — which is why `TypeName.parenthesizingOptionalExistentials`
  works on the rendered string rather than branching on `isOptional`. `DetailPresenting` in
  `Tests/Checks/Fixtures/Composition.swift` pins all four positions.
- **Sourcery only knows the declarations it parses.** `allVariables` / `allMethods` include an
  inherited requirement only when the inherited protocol is among the `--sources`. A protocol
  refining one from *another module* generates a mock missing those requirements, and the failure
  surfaces in the consumer's build as "type 'XMock' does not conform to protocol 'Y'" — never here.
  The fix belongs to whatever drives generation: pass the other module's sources too. **On the
  plugin path, `${SOURCERY_SOURCES}` closes this** — the plugin derives the target's whole
  dependency closure and splices it into the config it runs, so a refinement across any module
  boundary needs no config change (spec [001](specs/001-plugin-source-discovery/spec.md);
  `Tests/Checks/PluginFixture/Sources/App` is the reproducer, and
  `Tests/Examples/ExampleProjectSpm`'s `ProfilePersisting` is the same shape on the full lane). On
  the CLI path it stays the caller's job: the Duet reference app's `scripts/generate-mocks.sh`
  derives the set from `swift package dump-package` (every path dependency, plus the framework at
  its exact pin) rather than listing paths, so a new refinement needs no change to the script.

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
| fast | `Tests/Checks/run-checks.sh` | a Swift toolchain; ~10s |
| CLI | `Tests/Checks/run-cli-checks.sh` | a Swift toolchain; ~30s cold, seconds warm |
| plugin | `Tests/Checks/run-plugin-checks.sh` | a Swift toolchain and, once, the network; ~1 min cold |
| xcode | `Tests/Checks/run-xcode-checks.sh` | Xcode, `xcodegen` and, once, the network; ~35s |
| full | `cd Tests/Examples/ExampleProjectSpm && ./test-ios.sh` | an iOS Simulator; minutes |

Both check lanes provision Sourcery through `Tests/Checks/ensure-sourcery.sh`, which reads the pin
from `Scripts/engine-pin.sh`; `SOURCERY=/path/to/sourcery` overrides it in either lane.

The fast lane runs every template in its `TEMPLATES` list over `Tests/Checks/Fixtures`, diffs each
output against `Tests/Checks/Snapshots/`, typechecks the fixtures **and all generated files
together** under `-swift-version 5 -strict-concurrency=complete` and `-swift-version 6` at zero
diagnostics, then runs `Tests/Checks/Behaviour/Main.swift` — plain assertions in one executable, no
test framework. Compiling every template's output in one invocation is what keeps a mock and a
Component of the same protocol from disagreeing about isolation.

Adding a template is one line in `TEMPLATES` plus a recorded snapshot.

The plugin lane builds `Tests/Checks/PluginFixture` — a package whose targets are one per config
shape, over a three-level dependency chain (`App` → `Middle` → `Leaf`, with `ExternalKit` arriving
through `Middle` from a second package) — and then reads what the plugin wrote: the synthesized
configs, the generated code, and the build's own outcome. Its four red controls live in
`Tests/Checks/PluginFixtureRed/`, one package each, because build planning runs *every* target's
plugin: a plan-time error in one target fails the build for all of them, so no `--target` can
isolate a red control that shares a package with a green one. See `Tests/Checks/README.md`.

The Xcode lane covers the other half of the same plugin. `XcodeBuildToolPlugin` is handed no package
graph, no dependency edges and no shipped templates, so almost nothing the plugin lane asserts
carries over, and until this lane existed that half of the file was typechecked but never run. It
builds `Tests/Checks/XcodeFixture` one scheme at a time — four macOS framework targets, so no
simulator — and reads the synthesized configs and generated code the same way. Both its projects are
generated by `xcodegen` from a committed `xcodegen.yml` and are not committed: the spec is what a
reviewer reads, and `project.pbxproj` is generated identifiers.

The full lane is Quick + Nimble specs in
`Tests/Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/`, driven by the prebuild plugin.
It covers what the fast lane structurally cannot: RxSwift smart defaults, the RIBs
external-annotation pattern, type erasure, and the plugin itself.

`test-ios.sh` resolves whatever iOS runtime is installed; override with `DESTINATION`, `OS_VERSION` or
`DEVICE_NAME`.

### What each artifact covers

| lane | file | covers |
|------|------|--------|
| fast | `Tests/Checks/Snapshots/Mocks.generated.swift` | the generated mocks, as a reviewable diff |
| fast | `Tests/Checks/Snapshots/Components.generated.swift` | the generated Components, as a reviewable diff |
| fast | `Tests/Checks/Behaviour/Main.swift` | call counting, handlers, async suspension, nonisolated access off the main actor, subject-driven streams, cancellation counting, composites; for Components: forwarding identity, per-Component ownership, settable forwarding, parameter shapes, effectful getters |
| CLI | `Tests/Checks/run-cli-checks.sh` | `generate` transparency against the fast lane's snapshot; determinism across runs; `validate` red on a mutated input, an unlisted file, a hand-edited body, a wrong bundle tag, a `--template`/`--args` pair the block does not record; `imprint` recovery |
| plugin | `Tests/Checks/run-plugin-checks.sh` | the derived source closure (splice, sort, absolute paths); passthrough of everything else; the defaults the plugin supplies and the ones it must not; bare template-name resolution and the local file that outranks a shipped one; `args.testable` inserted, declined and left alone; determinism between builds; two configs on one target; and four red controls — a wrong `output:`, a template collision, an unknown template name, a `package:` the plugin must leave alone |
| xcode | `Tests/Checks/run-xcode-checks.sh` | the `XcodeBuildToolPlugin` path: config discovery through the target's own directory; the expansion being the target's own input directories and nothing else; a hand-listed `${SOURCERY_PROJECT}` entry that is scanned; passthrough; the defaults; determinism; a target depending on a sibling target; and one red control — a bare template name, which has no package graph to resolve against here |
| full | `SwiftSourceryTemplatesMocksSpec.swift` | mock instantiation, call counting, handler execution |
| full | `EscapingClosureMocksSpec.swift` | `@escaping` preservation — capture, async dispatch |
| full | `ReturnTypeOverloadMocksSpec.swift` | return-type-only overload disambiguation |
| full | `SwiftSourceryTemplatesTypeErasureSpec.swift` | type erasure wrapper conformance |

`Tests/Checks/README.md` maps construct → fixture.

### CI

`.github/workflows/ci.yml` runs all five lanes on every push: fast, CLI, plugin and xcode in
parallel, full gated on fast. A push touching only `**.md` skips all five. Xcode is
pinned via `XCODE_VERSION` because the fast lane's gate is *zero diagnostics*: a runner image whose
compiler emits one new warning would turn it red for a reason unrelated to the templates. The gate has
been measured to hold on Swift 6.3.3 (Xcode 26.6) and Swift 6.4 (Xcode 27 beta 4), so the pin is for
reproducibility rather than fragility. Bumping it means re-running the lanes locally on the new
version first.

`.github/workflows/release.yml` runs on tag pushes only (which ci.yml deliberately skips), and
routes two tag shapes to two jobs. A `templates-X.Y.Z` tag publishes the artifact bundle a
`Package.swift` pin can name, as a prerelease. A bare `X.Y.Z` tag runs
`Scripts/check-pinned-templates.sh` — which refuses to publish unless the pinned bundle's
`templates/` is byte-identical to the commit's — then `Scripts/assemble-release.sh`, and attaches
the assets to the tag's GitHub release.

## Cutting a release

1. Run all three lanes green
2. Regenerate the reference consumer (`modaal-firebase-wrappers`) against `master` and record the size
   and shape of its diff. A release whose consumer impact was not measured is not ready to tag
3. Write the `CHANGELOG.md` entry **before** tagging. It is written for a consumer deciding whether to
   bump: what the generated output looks like now, what can fail after a regenerate and how to fix it,
   what to do beyond bumping the tag
4. Tag `master`. There is no release branch
5. The tag push runs `.github/workflows/release.yml`, which publishes the release assets:
   `Scripts/assemble-release.sh <tag>` builds the `mock-templates` CLI universal
   (arm64 + x86_64), vendors the Sourcery engine at the `Scripts/engine-pin.sh` pin (the download
   is checksum-verified against it), smoke-runs `generate` + `validate` from the assembled layout,
   and emits
   `swift-sourcery-templates-<tag>.artifactbundle.zip`, `mock-templates-<tag>-macos.zip`, a
   `.sha256` beside each, and the release-notes body. Rehearse it locally with
   `Scripts/assemble-release.sh <version>` — everything lands in `.build/release-assets/`

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Sourcery | 2.3.0 | code generation engine (binary artifact); the pin of record is `Scripts/engine-pin.sh`, read by name by `Scripts/assemble-release.sh` when vendoring the engine into the release bundle and by `Tests/Checks/ensure-sourcery.sh` when provisioning it for the check lanes |
| swift-argument-parser | 1.3.0+ | the `mock-templates` CLI's command-line surface |
| XcodeGen | 2.44.1 | generates the Xcode lane's fixture projects from their committed specs — `brew install xcodegen`; contributors and CI only, never a consumer's dependency |
| Quick | 7.3.0 | BDD test framework (full lane) |
| Nimble | 13.0.0 | matchers (full lane) |
| RxSwift | 6.6.0 | example protocols, smart defaults |
| RIBs | 0.16.1 | example protocols, external annotation pattern |
| Alamofire | 4.9.1 | example dependency |

## Consumers

- **[modaal-firebase-wrappers](https://github.com/modaal-agent/modaal-firebase-wrappers)** — the
  reference consumer: 34 mocks across 7 modules, pre-generated and committed. Its
  `scripts/generate-mocks.sh` is the adopter pattern worth copying — templates cloned at a pinned
  tag, annotations in their own directory, one output file per module, `TEMPLATES_DIR` override for
  local iteration. Regenerate it when measuring a release's consumer impact.
- **The Duet reference app** — drove 0.2.15 and the Component template. 93 `/// sourcery:
  CreateMock` annotations including an `<X>Dependency` protocol at each of its 13 composition
  levels, built with `-strict-concurrency=complete`; the `Tests/Checks/Fixtures/` shapes are taken
  from it. The shape the Component template emits is specified in `modaal-agent`'s
  `specs/100-android-parity/27-duet-composition-shape.md` — §2 for the rule, §13 for the
  macro-vs-template measurement behind choosing a template.

## Open items

- **`public` access modifier on generated mocks.** Mock classes and their members are `internal`, so
  a consumer shipping mocks in a separate SPM product needs `@testable import`. Making them `public`
  touches `MockGenerator.swift` (class declaration, initializer), `MockMethod.swift` (func,
  `<name>CallCount`, `<name>Handler`) and `MockVar.swift` (the variable, `GetCount` / `GetHandler` /
  `SetCount`). Decide whether it is the default or gated behind an annotation (`sourcery:
  publicMock`) or a template arg (`--args publicMocks`); `public` as the default is probably right,
  since mocks are always consumed from another module.
- **Effectful property requirements in the mock template.** `var x: T { get async throws }` is
  parsed by Sourcery (`Variable.isAsync`, `Variable.throws`) and ignored by `Mocks.swifttemplate`,
  which emits a plain property that does not satisfy the requirement. Fixing it means always
  emitting a computed property with a `get async throws { }` accessor plus a separate backing store
  — a new naming convention, so it was left out of 0.2.15 rather than guessed at. No consumer uses
  the shape. The Component template **does** forward it (`Tests/Checks/Fixtures/Forwarding.swift`,
  `ProfileDependency`), because forwarding an effectful requirement is a pass-through and mocking
  one is not.
