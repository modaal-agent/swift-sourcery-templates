# Agent Handoff Guide

This document captures working context for AI agents continuing work on this project.

## Current State (2026-04-19)

**Latest tag:** 0.2.12 (pre-fix)
**Unreleased changes:** `@escaping` attribute preservation fix + tests (not yet tagged)

### Recent Fix: @escaping Preservation

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
2. For complex types (RxSwift): `smartDefaultValueImplementation()` and `hasComplexTypeWithSmartDefaultValue()`

### Adding a new annotation

1. `templates/Utility/Annotations.swift` — parsing logic
2. `templates/Mocks/MockVar.swift` or `MockMethod.swift` — consuming the annotation
3. Update CLAUDE.md annotations table

### Modifying the SPM plugin

1. `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`
2. Conditional compilation for Swift 5.x vs 6.0+ API differences
3. Test by building the example project

## Testing

### Test Framework

Quick + Nimble (BDD-style specs). Tests live in:
```
Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/
```

### Running Tests

```bash
cd Examples/ExampleProjectSpm
./test-ios.sh
```

The script runs `xcodebuild test` on an iOS Simulator. The prebuild plugin generates mocks before compilation.

### Test Structure

| File | What it tests |
|------|---------------|
| `SwiftSourceryTemplatesMocksSpec.swift` | Basic mock instantiation, call counting, handler execution |
| `EscapingClosureMocksSpec.swift` | @escaping attribute preservation (capture, async dispatch) |
| `SwiftSourceryTemplatesTypeErasureSpec.swift` | Type erasure wrapper conformance |

### Adding Tests for Template Changes

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

- **[modaal-firebase-wrappers](https://github.com/modaal-agent/modaal-firebase-wrappers)** — Primary consumer. Uses CLI mode to pre-generate mocks for 32 Firebase protocol wrappers. Templates pinned to tag `0.2.12`. The `@escaping` fix was driven by this project's need to test Combine streaming publishers with mock snapshot listeners.

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

- **`@Sendable` preservation:** Not yet needed by any consumer, but the same pattern as `@escaping` would apply — check `typeName.attributes["Sendable"]`.
- **CocoaPods example:** Less maintained than the SPM example. The `.sourcery-mocks.yml` config and `Podfile` may be outdated.
