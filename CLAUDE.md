# Claude Code Instructions

## Project Overview

Swift code-generation templates for [Sourcery](https://github.com/krzysztofzablocki/Sourcery). Two templates:

1. **`Mocks.swifttemplate`** — generates protocol mock classes for unit testing
2. **`TypeErase.swifttemplate`** — generates type erasure wrappers for protocols with associated types

Distributed as an **SPM build-tool plugin** (`SourcerySwiftCodegenPlugin`) and also usable standalone via Sourcery CLI.

## Repository Layout

```
CHANGELOG.md                        # Per-release: generated-output diff, breaking changes, adoption
templates/                          # Template source (the core product)
  Mocks.swifttemplate               # Entry point — includes all Mocks/* files, filters by CreateMock annotation
  TypeErase.swifttemplate            # Entry point for type erasure
  _header.swifttemplate              # Shared header — imports, SwiftLint directives
  Mocks/
    MockGenerator.swift             # Orchestrator: iterates protocols, emits class shells
    MockMethod.swift                # Method mocking: func signature, handler closure, call count
    MockVar.swift                   # Variable mocking: get/set tracking, smart defaults
    SourceCode.swift                # AST builder: SourceCode + TopScope for indented output
    SourceryRuntimeExtensions.swift # TypeName extensions: default values, RxSwift smart defaults
  Utility/
    Annotations.swift               # Parses sourcery: annotations (const, init, handler, methodName)
    Generics.swift                  # Generic type parsing with constraints
    String.swift                    # String utilities respecting nested type brackets
    StringLettercase.swift          # Case conversion (camelCase, snake_case, etc.)

Plugins/SourcerySwiftCodegenPlugin/ # SPM prebuild plugin
  SourcerySwiftCodegenPlugin.swift  # Locates Sourcery binary, exports env vars, runs codegen

Checks/                             # Fast lane — no simulator, no third-party packages
  run-checks.sh                     # generate → snapshot diff → typecheck ×2 → behaviour
  Fixtures/                         # protocol shapes taken from consumers (WikiMemory)
  Snapshots/Mocks.generated.swift   # recorded generated output; --record to update
  Behaviour/Main.swift              # runtime assertions, one executable, no test framework

Examples/
  ExampleProjectSpm/                # Full lane — RxSwift/RIBs/type erasure/plugin (SPM-based)
    Package.swift
    test-ios.sh                     # CI script: xcodebuild test on iOS Simulator
    Sources/ExampleProjectSpm/
      Protocols/Protocols.swift     # All test protocols (400+ lines, comprehensive patterns)
    Sources/ExampleProjectSpmTests/
      SwiftSourceryTemplatesMocksSpec.swift       # Mock functionality tests (Quick/Nimble)
      EscapingClosureMocksSpec.swift              # @escaping preservation tests
      SwiftSourceryTemplatesTypeErasureSpec.swift # Type erasure tests
      SourceryAnnotations/
        RIBs+SourceryAnnotations.swift           # External protocol annotations pattern
  ExampleProjectCocoapods/          # Legacy CocoaPods example (less maintained)

Package.swift                       # Plugin package definition
```

## Running Tests

Two lanes. **Start with the fast one** — a template edit that breaks a shape shows up in seconds, and
the snapshot diff is the only place generated output is reviewable.

```bash
Checks/run-checks.sh              # snapshot + both language modes + behaviour, ~10s
Checks/run-checks.sh --record     # after reviewing the diff, rewrite the snapshot

cd Examples/ExampleProjectSpm && ./test-ios.sh    # RxSwift, RIBs, type erasure, the plugin
```

Run both before cutting a tag. The example script builds and runs on an iOS Simulator; the SPM
build-tool plugin runs Sourcery as a prebuild step — generated mocks land in DerivedData, not in the
source tree, which is why `Checks/Snapshots/` exists.

CI (`.github/workflows/ci.yml`) runs both on every push, fast lane first. Xcode is pinned there — see
AGENTS.md for why and what bumping it requires.

## How Mock Generation Works

### Annotation → Template → Output

1. Protocol annotated with `/// sourcery: CreateMock` (directly or via empty extension)
2. Sourcery parses Swift source, builds type graph
3. `Mocks.swifttemplate` filters to annotated protocols, calls `MockGenerator.generate()`
4. For each protocol:
   - `MockVar.from(type)` generates variable mocking (get count, handlers, defaults)
   - `MockMethod.from(type)` generates method mocking (call count, handler closure, fallback)
5. Output: one `class <Protocol>Mock: <Protocol>` per protocol

### Generated Mock API Pattern

```swift
// For protocol method:
//   func fetchData(id: String, completion: @escaping (String) -> Void)

// Generated:
func fetchData(id: String, completion: @escaping (String) -> Void) {
    fetchDataCallCount += 1
    if let __fetchDataHandler = self.fetchDataHandler {
        __fetchDataHandler(id, completion)
    }
}
var fetchDataCallCount: Int = 0
var fetchDataHandler: ((_ id: String, _ completion: @escaping (String) -> Void) -> ())? = nil
```

### Concurrency Emission (since 0.2.15)

The generated file must compile with zero diagnostics under `-swift-version 5
-strict-concurrency=complete` **and** `-swift-version 6`. Four rules produce that, and
`Checks/run-checks.sh` enforces it:

| source construct | emission | where |
|---|---|---|
| protocol attribute `@MainActor` / `@*Actor`, or `sourcery: globalActor` | attribute line before `class` | `MockGenerator.swift`, via `Type.globalActorAttributeName` |
| `nonisolated` member of an isolated protocol | `nonisolated` on the member, `nonisolated(unsafe)` on its counter and handler | `MockMethod.storageIsolationDecl`, `MockVar.storageIsolationDecl` |
| `method.isAsync` | ` async` in the signature and the handler type, `await` at the handler call | `MockMethod.asyncDecl` |
| `@Sendable` closure parameter | the attribute in the signature and the handler type | `MethodParameter.closureAttributesDecl`, shared with `@escaping` |
| protocol refines `Sendable` | `final class …, @unchecked Sendable` | `MockGenerator.swift`, via `Type.requiresUncheckedSendable` |

`nonisolated(unsafe)` is what a mutable stored property outside the actor requires — a plain
`nonisolated var` on a stored property is rejected. The modifiers are emitted **only** when the mock
class carries a global actor (`Type.emitsNonisolatedMembers`); on a non-isolated mock they would be
noise.

Member-level global actors are deliberately **not** propagated: a non-isolated witness satisfies a
`@MainActor` requirement, and propagating would make the mock uncallable from a non-isolated test
body. `Checks/Fixtures/Isolation.swift`'s `TimelineBuildable` is the fixture that keeps this true.

### Key Files for Method Signature Generation

When modifying how mock method signatures are generated, these are the critical locations in `MockMethod.swift`:

| Line | What it generates | Key expression |
|------|-------------------|----------------|
| `parametersDecl` | `func` parameter list | `typeName.name` with `@escaping` prefix |
| `mockHandlerImpl` | `var handler:` closure type | `typeName.name` with `@escaping` prefix |
| `methodParametersDecl` | Joins all parameters | Calls `parametersDecl` per parameter |
| `returnTypeDecl` | `-> ReturnType` | `returnTypeName.name` |
| `mockMethodHandlerReturnType` | Handler return type | `returnTypeName.name` |

### SourceryRuntime API (for template authors)

Key properties on `MethodParameter`:
- `name` — internal parameter name
- `argumentLabel` — external label (nil = `_`)
- `typeName.name` — type without attributes (e.g., `(String) -> Void`)
- `typeName.asSource` — type with ALL attributes (e.g., `@escaping (String) -> Void`)
- `typeName.attributes` — `[String: [Attribute]]` dict (check `["escaping"]` for `@escaping`)
- `typeName.isClosure` — whether the type is a closure
- `inout` — whether the parameter is `inout`

Key properties on `TypeName`:
- `name` — base type string
- `asSource` — full declaration including attributes
- `isOptional`, `isVoid`, `isArray`, `isDictionary`, `isTuple`, `isClosure`
- `unwrappedTypeName` — type without optional wrapping
- `attributes` — type attributes (`@escaping`, etc.)
- `generic` — generic type info if applicable

## Annotations Reference

| Annotation | Target | Effect |
|------------|--------|--------|
| `CreateMock` | Protocol or extension | Generate mock class |
| `TypeErase` | Protocol | Generate type erasure wrapper |
| `associatedType = "T: Constraint"` | Protocol | Declare associated type for type erasure |
| `genericType = "T: Constraint"` | Method | Declare generic type parameter |
| `annotatedGenericTypes = "{T}"` | Parameter | Mark parameter as using generic placeholder |
| `methodName = "customName"` | Method | Override generated mock variable name |
| `const` | Variable | Use `let` instead of `var` in mock |
| `init` | Variable | Include in mock's `init()` |
| `handler` | Variable | Generate handler closure for variable |
| `import = "Module"` | Protocol | Add `import Module` to generated output |
| `ObjcProtocol` | Protocol | Generate `NSObject` superclass for mock |
| `globalActor = "MyIsolation"` | Protocol | Declare the mock's global actor when the attribute name does not end in `Actor` |
| `uncheckedSendable` | Protocol | Force `@unchecked Sendable` when the `Sendable` refinement is not visible to Sourcery (e.g. inherited through an unresolved protocol) |
| `subject = "CurrentValue"` / `"Passthrough"` | Variable / method | Choose the subject backing an `AnyPublisher` member |

## External Protocol Annotation Pattern

To generate mocks for protocols defined in external packages (without modifying their source), use empty extensions with annotations:

```swift
// In your project's SourceryAnnotations/ directory:
import ExternalFramework

/// sourcery: CreateMock
extension ExternalProtocol {}
```

This is how RIBs protocols are annotated in the example project. Sourcery picks up annotations from extensions on the protocol.

## Template Args (CLI / Config)

Pass via `--args` (CLI) or `args:` (YAML config):

| Arg | Effect |
|-----|--------|
| `import=Module` | Add `import Module` to output |
| `testable=Module` | Add `@testable import Module` to output |
| `excludedSwiftLintRules=[rule1,rule2]` | Add `//swiftlint:disable` directives |

Multiple imports: use repeated `--args` flags or YAML array syntax.

## Common Pitfalls

- **`typeName.name` vs `typeName.asSource`**: `.name` strips type attributes (`@escaping`, `@Sendable`). Use `.name` for type identity comparisons; check `typeName.attributes` explicitly when emitting declarations. `MethodParameter.closureAttributesDecl` is the one place that does this — add new closure attributes there, not at the two call sites.
- **`@autoclosure`**: Valid on function parameters but NOT on closure type parameters. This is why `asSource` cannot be used wholesale in handler closure types — each attribute is opted into explicitly.
- **Handler closure parameter escaping**: The handler's closure type must preserve `@escaping` on inner closure parameters so the handler implementation can capture/dispatch them async.
- **Method name disambiguation**: When a protocol has overloaded methods, the template automatically falls back to long-form names (including parameter labels) to avoid duplicate mock variable names. If long-form names also collide — overloads sharing the same name *and* parameter list, differing only by return type, e.g. a refining protocol overriding `func data() -> [String: Any]?` with `func data() -> [String: Any]` — a sanitized return-type suffix is appended to the mock variable names (`dataStringAnyOptionalHandler` vs `dataStringAnyHandler`). The naming convention is deterministic: optional types contribute an `Optional` suffix; bracket/colon/space characters in the type are stripped and the remainder is camel-cased. See `ReturnTypeOverloadMocksSpec.swift` for the canonical reproducer (mirrors Firebase iOS SDK's `QueryDocumentSnapshot : DocumentSnapshot` shape).
- **Generated mock access level**: Mock classes and all their members are currently `internal` (no access modifier). Consumers shipping mocks in a separate SPM product need `@testable import` to access them. See AGENTS.md "Open Items" for the planned fix — `public` should be added to class, init, all vars, and all funcs across MockGenerator.swift, MockMethod.swift, and MockVar.swift.
- **Non-Sendable mocks and `async`**: a mock of a non-isolated protocol is a non-Sendable class. Constructing it on the main actor and then calling a nonisolated `async` member sends it across an isolation boundary, which the Swift 6 language mode rejects — the test body has to be non-isolated too. This is Swift's rule, not a template defect; `Checks/Behaviour/Main.swift`'s `checkAsync` documents it in place.
- **Smart-default ordering**: `smartDefaultValueImplementation` matches `AnyPublisher` before `AnyCancellable` before `Disposable` before the RxSwift generics. Adding a case in the wrong order silently changes which branch a type takes — the snapshot gate is what catches it.
