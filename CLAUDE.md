# Claude Code Instructions

## Project Overview

Swift code-generation templates for [Sourcery](https://github.com/krzysztofzablocki/Sourcery). Two templates:

1. **`Mocks.swifttemplate`** — generates protocol mock classes for unit testing
2. **`TypeErase.swifttemplate`** — generates type erasure wrappers for protocols with associated types

Distributed as an **SPM build-tool plugin** (`SourcerySwiftCodegenPlugin`) and also usable standalone via Sourcery CLI.

## Repository Layout

```
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

Examples/
  ExampleProjectSpm/                # Primary test project (SPM-based)
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

```bash
cd Examples/ExampleProjectSpm
./test-ios.sh
```

The test script builds and runs on iOS Simulator. The SPM build-tool plugin runs Sourcery as a prebuild step — generated mocks land in DerivedData, not in the source tree.

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

- **`typeName.name` vs `typeName.asSource`**: `.name` strips type attributes (`@escaping`). Use `.name` for type identity comparisons; check `typeName.attributes` explicitly when emitting declarations.
- **`@autoclosure`**: Valid on function parameters but NOT on closure type parameters. Don't blindly use `asSource` in handler closure types — check for specific attributes.
- **Handler closure parameter escaping**: The handler's closure type must preserve `@escaping` on inner closure parameters so the handler implementation can capture/dispatch them async.
- **Method name disambiguation**: When a protocol has overloaded methods, the template automatically falls back to long-form names (including parameter labels) to avoid duplicate mock variable names.
- **Generated mock access level**: Mock classes and all their members are currently `internal` (no access modifier). Consumers shipping mocks in a separate SPM product need `@testable import` to access them. See AGENTS.md "Open Items" for the planned fix — `public` should be added to class, init, all vars, and all funcs across MockGenerator.swift, MockMethod.swift, and MockVar.swift.
