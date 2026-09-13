# 006 — Print a mock inside an outer sandbox, and generate `#if` members under their condition

**Status:** Proposed. Nothing here is implemented. §1 is what was measured, §2 the shape this proposes,
§3 ten decisions with a recommendation in each — none is ruled — and §4 the phasing.

**Ruled on 2026-09-13, before this spec was written:** one spec and one branch for all three parts
(§2.1 the script, §2.2 the plugin, §2.3 the templates), and the plugin's `TMPDIR` (§2.2) inside the
scope of this spec and its release.

**Ruled on 2026-09-13, after it was written — §7:** the annotation of D4 (b) and (d) is spelled
`// sourcery: if = "<condition>"`. D4 itself and the other nine decisions are not ruled.

**Ruled on 2026-09-13 — §8:** D4 (b), with §7's spelling: a condition comes from the `if` annotation only,
and the templates read no source file. §8.2 names what that supersedes in §2.3, §2.4, D5, D6, §4 and §7.

**Ruled on 2026-09-13 — §9:** D6. An `import` is emitted inside `#if canImport(<M>)` when an `if` annotation
names `canImport(<M>)`, or when its `args.import` item is written `<M> // if canImport`.

**Ruled on 2026-09-13 — §10:** D1 (a), D2 (c), D3 (a), D7 (a), D8 (a), D9 (a), D10 (a); §9.5, where
`args.testable` takes the manual form; and §6's two questions.

**Implemented on 2026-09-13 — §11:** P1 to P7 landed on the branch; §11.2 names where the implementation
differs from §2 to §10.

**Measurements:** every number, path and quoted line in §1 was produced on 2026-09-13 on macOS 26.6.2
(25G83) with Xcode 26.6 (17F113), Swift 6.3.3 (swiftlang-6.3.3.1.3), `/bin/bash` 3.2.57 and Sourcery
2.3.0, against `master` at `296e365`. The Sourcery source read is tag `2.3.0` of
`krzysztofzablocki/Sourcery`, the newest tag on 2026-09-13. Times are the `real` time of one
invocation. The probes ran in the session scratchpad, outside the repository:

| probe | what it is |
| --- | --- |
| `e2e` | SwiftPM, `.macOS(.v13)`, this checkout by `path:`. `Feature` declares `/// sourcery: ProtocolMock` `protocol Service { func load() -> Int }`; test target `FeatureTests` applies the plugin with a config holding `templates: [Mocks]` and nothing else |
| `e2e-pass`, `e2e-builddir` | `e2e` against a copy of this checkout whose plugin carries one of the two patches of §1.4 |
| `sbx` | SwiftPM, one library target `Lib`, no plugin |
| `ifprobe1` to `ifprobe4` | Swift source directories run through Sourcery 2.3.0 with `templates/Mocks.swifttemplate`, dump templates, and the scanner prototype of §1.9 |

A sandboxed row runs its command as `sandbox-exec -p <profile>`. `<USER_TEMP>` is
`getconf DARWIN_USER_TEMP_DIR` resolved with `pwd -P`, `/private/var/folders/kb/…/T`. Every sandboxed row
exports `TMPDIR` as a directory inside the probe.

| profile | text |
| --- | --- |
| `allow-all` | `(version 1)(allow default)` |
| `deny-temp` | `(version 1)(allow default)(deny file-write* (subpath "<USER_TEMP>"))` |
| `deny-temp+items` | `deny-temp`, then `(allow file-write* (subpath "<USER_TEMP>/TemporaryItems"))` |
| `deny-temp+items+swiftpm` | `deny-temp+items`, then an `allow file-write*` regex for `<USER_TEMP>/TemporaryDirectory.*` and `<USER_TEMP>/*.lock` |

**Scope of the change:**

- the script: `skills/swift-sourcery-mocks/scripts/print-mocks.sh`, `references/printing-mocks.md`;
- the plugin: `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`;
- the templates: a new `templates/Utility/CompilationConditions.swift`, `Mocks/MockGenerator.swift`,
  `Mocks/MockVar.swift`, `Component/ComponentGenerator.swift`, `TypeErase.swifttemplate`, and the include
  lists of the three entry points;
- the gates: a new `Tests/Checks/Fixtures/Conditional.swift`, `Tests/Checks/run-checks.sh`,
  `Tests/Checks/run-plugin-checks.sh`, `Tests/Checks/run-xcode-checks.sh`, `Tests/Checks/README.md`, the
  re-recorded `Tests/Checks/Snapshots/`, and subject to D8 a fixture under `Tests/Examples/ExampleProjectSpm`;
- the documents: `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `references/troubleshooting.md`; subject to
  D4, `templates/Annotations/AnnotationRegistry.swift` and every table `Scripts/render-annotations.sh`
  renders;
- a release: `templates-X.Y.Z`, the pin commit, the bare `X.Y.Z` tag.

**Superseded in part by §8.2:** `AnnotationRegistry.swift` and the rendered tables are in scope without
the D4 condition.

**Not in scope:** SwiftPM's own writes under `<USER_TEMP>/TemporaryItems` (§1.3), which neither the script
nor the plugin issues; the `mock-templates` CLI; DISCOVERY 67 items 1 and 2 (the network); the lab's
`lab/v2/bin/mktemp`, `lab/v2/bin/swift` and its ported 0.9.0 checkout, which the lab keeps or retires.

**Obsoletes:** `specs/005-print-mock-without-build/spec.md` §2.2 steps 1 and 2 in part, if D2 is ruled
anything other than (d): both `swift build` commands gain `--disable-sandbox` under a condition. Nothing in
`specs/001-plugin-source-discovery/`: neither `spec.md` nor `followup-xcode-lane.md` contains `TMPDIR`
(`grep`, 0 matches).

**Follows:** the lab repository `modaal-agent-devto-mock-generation-lab`, `DISCOVERY.md` entries 67, 69,
70 and 71, and that repository's `specs/002-real-subtree-multi-step/spec.md` §17.6, which leaves "a
setting in `print-mocks.sh` upstream for the `mktemp` template and for `--disable-sandbox`" open for the
owner of this repository.

---

## 0. TL;DR

1. `print-mocks.sh:80` calls `mktemp` with no template, and macOS 26.6.2's `mktemp` then creates the file
   in `<USER_TEMP>` whatever `TMPDIR` holds. Under `deny-temp` the script exits 1 in 0 s before
   `swift build` runs (§1.1).
2. Inside any `sandbox-exec` profile, `allow-all` included, `swift build` exits 1 with
   `sandbox-exec: sandbox_apply: Operation not permitted` and `Invalid manifest`. The same command with
   `--disable-sandbox` exits 0. The script has no setting that adds the flag (§1.2).
3. With both fixed, the print under `deny-temp+items` fails inside the plugin's prebuild command. Sourcery
   builds the template with its own `swift build`, which receives no `TMPDIR` and writes lock files and
   `TemporaryDirectory.*` into `<USER_TEMP>`. A plugin that sets `TMPDIR` for the prebuild command prints
   the mock under `deny-temp+items` (§1.3, §1.4).
4. Sourcery 2.3.0 visits every clause of an `#if` and records no condition
   (`SyntaxTreeCollector.swift:289-291`), so a mock carries the members of every clause. DISCOVERY 69's
   shape gives `cannot find type 'UIImage' in scope` on macOS (§1.5). `Method` and `Variable` carry no
   source position; `Type` carries `path`, `bodyBytesRange` and `completeDeclarationRange` (§1.6).
5. A 132-line prototype template reads each member's and each protocol's condition from the source text
   through those three properties. Over this repository's fixtures, `ExampleProjectSpm`, `PluginFixture`,
   the 34 protocols of `modaal-firebase-wrappers` and the 89 protocols of the Firebase SDK checkout, its
   declaration counts disagree with Sourcery's on one protocol, one declared in both clauses of an `#if`
   (§1.9).
6. **Proposed:** the script keeps stderr in a variable and adds `--disable-sandbox` on a setting and on
   SwiftPM's diagnostic; the plugin sets `TMPDIR` under its build directory; the templates put each member,
   and each protocol, inside the `#if` its source declares around it. One branch, then one release.

**Superseded in part by §8:** item 5 records D4 (a), which is not built. In item 6 the templates put a
member or protocol inside the condition its `// sourcery: if = "<condition>"` annotations name (§7.1,
§8.4).

---

## 1. Measured

### 1.1 `mktemp` without a template ignores `TMPDIR`

With `TMPDIR` exported as a directory in the scratchpad:

| call | created in |
| --- | --- |
| `mktemp` | `<USER_TEMP>` |
| `mktemp -t x` | `<USER_TEMP>` |
| `mktemp -d` | `<USER_TEMP>` |
| `mktemp -q -t print-mocks` | `<USER_TEMP>` |
| `mktemp -p ""` | `TMPDIR` |
| `mktemp -p "$TMPDIR"` | `TMPDIR` |
| `mktemp "${TMPDIR%/}/tmp.XXXXXXXXXX"` | `TMPDIR` |

`man mktemp` on this machine: a `-t` template is created "based on the prefix and the
_CS_DARWIN_USER_TEMP_DIR configuration variable if available. Fallback locations if
_CS_DARWIN_USER_TEMP_DIR is not available are TMPDIR, the -p option's tmpdir if set, and /tmp", and "If no
arguments are passed or if only the -d flag is passed mktemp behaves as if -t tmp was supplied."

Under `deny-temp`, `mktemp` printed `mktemp: mkstemp failed on /var/folders/kb/…/T/tmp.GwdD4E3Mmd: Operation
not permitted` and exited 1; `mktemp -p "$TMPDIR"` exited 0. DISCOVERY 70 records the same on macOS 26.5.

`print-mocks.sh:80-81` is the script's only temporary file. It holds `swift build`'s stderr so that `:85`
can search it and `:90` and `:95` can print it. The Xcode lane (`:129-191`) writes under
`<DerivedData>/Build/Intermediates.noindex/PrintMocks` and creates no temporary file.

A command substitution keeps both the text and the status. Under `/bin/bash` 3.2.57 with
`set -eo pipefail`, `if ! err="$( { echo out; echo "line one" >&2; echo "sandbox-exec: sandbox_apply:
Operation not permitted" >&2; exit 3; } 2>&1 >/dev/null )"` took the failure branch, and
`grep -c sandbox_apply` over `$err` answered 1. On a command that exits 0, `$err` held its `warning:` line.

### 1.2 SwiftPM cannot start its sandbox inside another

In `sbx`, `swift build --target Lib --print-manifest-job-graph`:

| run | exit | stderr |
| --- | --- | --- |
| no outer sandbox | 0 | — |
| under `allow-all` | 1 | `sandbox-exec: sandbox_apply: Operation not permitted`, `error: 'pkg': Invalid manifest (compiled with: [… "-o", "<TMPDIR>/TemporaryDirectory.rqEUti/pkg-manifest"])`, and the first line again |
| under `allow-all`, with `--disable-sandbox` | 0 | — |

- `swift build --help` on 6.3.3 lists `--disable-sandbox  Disable using the sandbox when executing
  subprocesses.`
- DISCOVERY 71: none of the 24 `SWIFTPM_*` variables that Xcode 26.6's `swift-build`, `swift-package` and
  `swift-test` read turns the sandbox off. DISCOVERY 18: a `Package.swift` run with `--disable-sandbox`
  under the lab's profile could write inside its own tree only.
- DISCOVERY 17: every Swift run met `Invalid manifest` and spent three or four turns reaching
  `--disable-sandbox`, until a sentence in the prompt named it.
- `print-mocks.sh:82` and `:86-88` are the two `swift build` commands. `SCRATCH_PATH` (`:76-79`) is the
  script's only SwiftPM setting.

### 1.3 The print, one change at a time

In `e2e`, `print-mocks.sh FeatureTests Service`, each row on a fresh `SCRATCH_PATH` unless it says
otherwise. Script `c` replaces `:80` with `err="$(mktemp "${TMPDIR:-/tmp}/print-mocks.XXXXXXXXXX")"`;
script `d` is `c` with `--disable-sandbox` after `swift build` on both commands.

| row | script | plugin | profile | exit | real | stdout, or the last lines of stderr |
| --- | --- | --- | --- | --- | --- | --- |
| a | shipped | shipped | none | 0 | 10 s | the 17-line block |
| b | shipped | shipped | `deny-temp` | 1 | 0 s | `mktemp: mkstemp failed on /var/folders/kb/…/T/tmp.HW5Tgb8e0z: Operation not permitted` |
| c | `c` | shipped | `deny-temp` | 1 | 1 s | `sandbox-exec: sandbox_apply: Operation not permitted`, `print-mocks: planning FeatureTests failed` |
| d | `d` | shipped | `deny-temp` | 1 | 3 s | `error: encountered an I/O error (code: 1) while reading <scratch>/arm64-apple-macosx/debug/Feature.build/output-file-map.json` |
| d2 to d4 | `d` | shipped | `deny-temp` | 1 | 1–3 s | the same line; d2 re-used row d's scratch path, d3 and d4 each a fresh one |
| e | `d` | shipped | none | 0 | 8 s | the 17-line block |
| i | `d` | shipped | `deny-temp`, then `<USER_TEMP>/xcrun_db*` allowed as `lab/v2/sandbox-profile.sh:70` allows it | 1 | — | the `output-file-map.json` line |
| k | `d` | shipped | `deny-temp+items` | 1 | 5 s | `/usr/bin/env "xcrun" "--sdk" "macosx" "swift" "build" "-c" "release" "-Xswiftc" "-Onone" "-Xswiftc" "-suppress-warnings" "--disable-sandbox"`, then `error: InternalError(… Failed to parse target info (malformed(json: "error: permissionDenied", …` |
| m | `d` | shipped | `deny-temp+items+swiftpm` | 1 | 8 s | `[8/9] Linking SwiftTemplate`, `error: generate-dSYM command failed with exit code 1`, `error: Operation not permitted` |
| m′ | shipped | shipped | `deny-temp+items+swiftpm` | 1 | 0 s | row b's `mktemp` line |

- Row k's `swift build -c release` and row m's `Linking SwiftTemplate` are Sourcery's build of the
  template, run by the plugin's prebuild command. Row m's failure is the one DISCOVERY 67 item 3 reports.
- Row j repeated row e with a marker file touched first. `<USER_TEMP>` gained two lock files whose names
  are the path `<scratch>/plugins/outputs/pkg/FeatureTests/destination/SourcerySwiftCodegenPlugin/.sourceryBuild/SwiftTemplate/<uuid>/2.3.0/.build`
  truncated from the left, and at least seven `TemporaryDirectory.*` directories (the listing was cut at 15 lines). `TMPDIR` held the probe's directory
  throughout.
- Rows d and i fail in SwiftPM's plan of the root package, before any prebuild command runs. Row k differs
  from row d only by `<USER_TEMP>/TemporaryItems`; the runs of rows k, m and m′ added one entry there.
- The prebuild command is `Command.prebuildCommand(… environment: environmentVars …)`
  (`SourcerySwiftCodegenPlugin.swift:911-938`), `Command._prebuildCommand` before Swift 6.0 (`:939-968`).
  `environmentVars` is `context.environmentVars` (`:789`) plus `SOURCERY_TEMPLATES` (`:792`) and
  `SOURCERY_OUTPUT_DIR` (`:851`); for a package, `context.environmentVars` is `GIT_ROOT`, `SOURCERY_PACKAGE`
  and one `SOURCERY_TARGET_*` per target and dependency (`:1015-1031`). DISCOVERY 67 item 4 records
  SwiftPM printing that environment with no `TMPDIR`.
- `_createBuildCommands` (`:733`) builds the commands for both halves of the plugin: the `PluginContext`
  extension calls it at `:1106` and the `XcodePluginContext` extension at `:1217`.

### 1.4 The plugin with `TMPDIR` set

Two copies of this checkout, each with one change after `var sharedEnvironmentVars =
context.environmentVars` (`:789`):

- `pass`: `if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { sharedEnvironmentVars["TMPDIR"] = tmp }`
- `builddir`: `perTargetBuildDir.appending("tmp")` created with `FileManager.default.createDirectory` and
  set as `TMPDIR`. `perTargetBuildDir` is `<pluginWorkDirectory>/.sourceryBuild` (`:769-770`).

In `e2e-pass` and `e2e-builddir`, `print-mocks.sh FeatureTests Service`. Script `c` leaves SwiftPM's sandbox
on; script `d` turns it off.

| plugin | script | profile | `TMPDIR` | exit | result |
| --- | --- | --- | --- | --- | --- |
| `pass` | `d` | none | the probe's | 0 | the 17-line block; nothing new at depth 1 in `<USER_TEMP>`; `TMPDIR` gained the `.sourceryBuild` lock file and 13 `TemporaryDirectory.*` |
| `pass` | `d` | `deny-temp` | the probe's | 1 | the `output-file-map.json` line |
| `pass` | `d` | `deny-temp+items` | the probe's | 0 | the 17-line block |
| `pass` | `c` | none | the probe's | 0 | the 17-line block, identical to row a (`cmp`) |
| `pass` | `c` | none | unset | 0 | the 17-line block |
| `builddir` | `d` | none | the probe's | 0 | the 17-line block; nothing new at depth 1 in `<USER_TEMP>`; `.sourceryBuild/tmp` holds 11 entries |
| `builddir` | `d` | `deny-temp` | the probe's | 1 | the `output-file-map.json` line |
| `builddir` | `d` | `deny-temp+items` | the probe's | 0 | the 17-line block |
| `builddir` | `c` | none | the probe's | 0 | the 17-line block, identical to row a (`cmp`) |
| `builddir` | `c` | none | unset | 0 | the 17-line block |

- The first `pass` row shows the plugin process reading the `TMPDIR` of the `swift build` that runs it.
- The two `c` rows of each plugin shared one marker file, so what each wrote into `<USER_TEMP>` is not
  separated.
- The lab's port sets `TMPDIR` inside `--buildPath` with a script in place of the bundle's `sourcery`
  (lab spec 002, the `deps/v2/swift/swift-sourcery-templates` row of its ports table); `builddir` puts it
  in the same directory from the plugin.

### 1.5 Sourcery 2.3.0 and `#if`

- `SyntaxTreeCollector.swift:289-291` at tag `2.3.0`: `public override func visit(_ node:
  IfConfigDeclSyntax) -> SyntaxVisitorContinueKind { return .visitChildren }`. No other line of the file
  names `IfConfig`.
- `ifprobe1` through `Mocks.swifttemplate` with `--args import=Foundation` exits 0 and writes 171 lines:

  | protocol | source | the mock |
  | --- | --- | --- |
  | `AvatarRepositoryProtocol`, DISCOVERY 69's shape | `func uploadOwnPhoto(_ image: UIImage)` inside `#if canImport(UIKit)` | `uploadOwnPhoto(_:)` and its members, with no condition |
  | `Branching` | `func render() -> Int` under `#if os(iOS)`, `func render() -> String` under `#else` | both, named with the return-type suffix |
  | `Nested` | `var debugName` under `#if DEBUG`; `func tint(_ color: UIColor)` under an `#if canImport(UIKit)` nested in it | both, with no condition |
  | `WholeGuarded` | the whole protocol inside `#if canImport(UIKit)` | `WholeGuardedMock`, with no condition |

  `xcrun swiftc -typecheck -swift-version 6` over the source and the mock: 14 errors — 6 `cannot find type
  'UIImage' in scope`, 6 `cannot find type 'UIColor' in scope`, 2 `cannot find type 'WholeGuarded' in
  scope`.
- `ifprobe3`: `func render() -> Int` declared in both clauses of `#if os(iOS)` / `#else` gives two
  `rawMethods` entries and one `allMethods` entry; `methods` (`Type.swift:114-116`) and `allMethods` (from `:125`) both apply `uniqueMethodFilter`. `var mode:
  Int` under `#if FIXTURE_FLAG` and `var mode: String` under `#else` give two entries in both
  `rawVariables` and `allVariables`: `uniqueVariableFilter` compares name, `isStatic` and `typeName`
  (`Type.swift:107-109`).
- `MockMethod.from` (`MockMethod.swift:19-43`) and `MockVar.from` (`MockVar.swift:17-20`) read
  `allMethods` / `allVariables`, drop static members and members defined in an extension, and sort by the
  mock member name. The emitted order is not the declaration order.
- `ifprobe2`: a file holding `import UIKit` inside `#if canImport(UIKit)` gives `type.imports ==
  ["Foundation", "UIKit"]`, with no condition. `_header.swifttemplate:28-33` emits `args.import` and
  `args.testable` and reads no `type.imports`.
- `import UIKit` alone in a file, `xcrun swiftc -typecheck -swift-version 6`: `error: no such module
  'UIKit'`.

### 1.6 What SourceryRuntime 2.3.0 carries for a position

- `SourceryRuntime/Sources/macOS/AST/Type.swift`: `bodyBytesRange` (`:167`), `completeDeclarationRange`
  (`:171`), `path` (`:342`), `fileName` (`:366`).
- `Method.swift` and `Variable.swift`: no byte range, path or file name. Both carry `definedInTypeName` and
  `definedInType` (`Variable.swift:90`, `:100`).
- `SyntaxTreeCollector.swift:26-42` sets `bodyBytesRange` from the end of the declaration's first `{` to
  the start of its last `}`, and `completeDeclarationRange` from its first token after leading trivia to
  its end.

`ifprobe2` through a dump template:

- `path` is the path as it reached `--sources` (`Sources/A.swift`), and
  `FileManager.default.contents(atPath:)` inside the template reads it.
- The UTF-8 bytes of `bodyBytesRange` are the body text with its comments, `#if`, `#elseif` and `#endif`
  lines and a trailing `// trailing comment` on a directive line.
- `Refining: BaseInOtherFile`, declared in another file: the inherited `inherited()` reports
  `definedInTypeName == BaseInOtherFile`, and is the same object (`===`) as the entry in
  `BaseInOtherFile.rawMethods`.

### 1.7 Annotation values a condition needs

`ifprobe1` and `ifprobe2` through a dump template:

| source | `annotations` of the declaration |
| --- | --- |
| `/// sourcery: compilationCondition = "compiler(>=6.0)"` | `["compilationCondition": compiler(>=6.0)]` |
| `/// sourcery: compilationCondition = "canImport(UIKit, _version: 2)"` | `["compilationCondition": canImport(UIKit, _version: 2)]` |
| `/// sourcery: compilationCondition = "os(iOS) && !targetEnvironment(macCatalyst)"` | the value as written |
| `/// sourcery: compilationCondition = "os(iOS) \|\| os(tvOS)"` | the value as written |
| `// sourcery:begin: compilationCondition = "canImport(UIKit)"` … `// sourcery:end` around a method and a property inside a protocol body | each of the two carries `["compilationCondition": canImport(UIKit)]` |
| the same annotation in the protocol's own doc comment | the protocol carries it |
| `/// sourcery: #if canImport(UIKit)` | `["#if canImport(UIKit)": 1]` |

The ruled spelling is `if`, not `compilationCondition`; §7.2 measures it.

### 1.8 Swift accepts the shapes the emission needs

A file declaring a `struct`, then `#if canImport(Darwin)` / `import Darwin` / `#endif`, then a class whose
stored property and method sit inside `#if FIXTURE_FLAG`, then a function calling `sqrt`: `xcrun swiftc
-typecheck` exits 0 with no output under `-swift-version 6`, `-swift-version 6 -D FIXTURE_FLAG` and
`-swift-version 5 -strict-concurrency=complete`.

### 1.9 The scanner prototype

`Scan.swifttemplate`, 132 lines, in the scratchpad:

1. Every comment (`//`, nested `/* */`) and every string literal's contents (`"…"`, `"""…"""`, a
   backslash and the character after it) are replaced by spaces; newlines stay.
2. Per line: `#if C` pushes a frame; `#elseif C` adds a clause to it; `#else` marks it; `#endif` pops it.
   The condition at a position joins the frames with `&&`. A frame in clause `i` contributes
   `!(c0) && … && !(c(i-1)) && (ci)`; in `#else`, `!(c0) && … && !(cn)`.
3. On every other line, `func`, `init`, `var` and `subscript` at bracket depth 0 — `(`, `[` and `{`
   counted — record a declaration under the current condition. A backticked name is skipped.
4. A protocol's own condition is the frame stack at the end of bytes 0 to
   `completeDeclarationRange.offset`; its members' are read from the bytes of `bodyBytesRange`.
5. The `n`-th scanned `func` or `init` is the `n`-th entry of `rawMethods` that passes the member filter,
   and the `n`-th `var` the `n`-th of `rawVariables`. A count that differs prints a mismatch.

Over `ifprobe1` to `ifprobe4` in one Sourcery run of 3.85 s, with the member filter "`definedInType` is
not an extension":

| construct (probe) | condition read |
| --- | --- |
| `uploadOwnPhoto` inside `#if canImport(UIKit)` (1) | `(canImport(UIKit))` |
| `#if os(iOS)` / `#elseif os(macOS)` / `#else`, one `func` in each (4) | `(os(iOS))`; `!(os(iOS)) && (os(macOS))`; `!(os(iOS)) && !(os(macOS))` |
| `#if canImport(UIKit)` nested in `#if DEBUG`, and a `var` after the inner `#endif` (1, 4) | `(DEBUG) && (canImport(UIKit))`; `(DEBUG)` |
| a `func` over four lines after `#if canImport(UIKit) // trailing comment`, and an `#elseif os(macOS)` overload (2) | `(canImport(UIKit))`; `!(canImport(UIKit)) && (os(macOS))` |
| `#if NEVER` inside a block comment; `@available(*, deprecated, message: "not a #if directive")`; `// a comment mentioning #if canImport(UIKit)` (2, 4) | no condition |
| `func labelled(for value: Int, init other: Int, _ body: (Int) -> Void)` and `` var `var`: Int { get set } `` (4) | one method and one variable, no condition |
| `extension Tricky { func deprecatedOne() {} func extra() {} }` in the same file (4) | not counted: 8 `rawMethods`, 6 of them outside the extension, 6 scanned |
| the whole protocol inside `#if canImport(UIKit)` (1); a protocol inside `#if canImport(AppKit)` / `enum Namespace { … }` (4) | `(canImport(UIKit))`; `(canImport(AppKit))` for `Namespace.NestedInside` |
| `inherited()` under `#if DEBUG` in `BaseInOtherFile`, read through `Refining` (2) | `(DEBUG)` in the owner's scan |

All 13 protocols matched their counts.

**The corpora.** The same template over real sources. With the first member filter, the Firebase SDK
checkout gave 5 mismatches in 4 protocols. A second dump showed their causes:

- `Itemable` and `Sectionable` (`FirebaseAuth/Tests/SampleSwift/AuthenticationExample/Utility/DataSourceProvider/DataSourceProtocols.swift`)
  carry in `rawVariables` the members of `Item` and `Section` from `Models/Section.swift`, with
  `definedInTypeName` naming `Item` or `Section` and `definedInType.isExtension == false`.
- `InstallationsProtocol` is declared in `FirebaseSessions/Sources/Installations+InstallationsProtocol.swift:21`
  and in `FirebaseAppDistributionInternal/Sources/Internal/InstallationsProtocol.swift:20`; Sourcery keeps
  one type holding both files' members.
- `_JSONStringDictionaryDecodableMarker` is declared twice in
  `FirebaseSharedSwift/Sources/third_party/FirebaseDataEncoder/FirebaseDataEncoder.swift`, at `:87` and
  `:91`, one in each clause of an `#if`.

`Scan2.swifttemplate` adds `definedInTypeName?.name == type.name` and `definedInType?.path == type.path` to
the member filter. Its results:

| corpus | protocols with a position | count mismatches | protocols inside `#if` | members inside `#if` |
| --- | ---: | ---: | ---: | ---: |
| `ifprobe1` to `ifprobe4` | 13 | 1: `SameInBoth` | 2 | 15 |
| `Tests/Checks/Fixtures` | 43 | 0 | 0 | 0 |
| `Tests/Examples/ExampleProjectSpm/Sources` | 40 | 0 | 0 | 0 |
| `Tests/Checks/PluginFixture/Sources` and `Tests` | 6 | 0 | 0 | 0 |
| `modaal-firebase-wrappers` at `1f5cf93`, the 41 directories holding its `.swift` files outside `.build`, `Mocks/` and `*.generated.swift` | 34 | 0 | 0 | 0 |
| its `.build/checkouts/firebase-ios-sdk`, 954 `.swift` files | 89 | 1: `_JSONStringDictionaryDecodableMarker` | 17 | 2 |

- The first-filter runs took 3.85 s (the probes), 4 s (the 41 directories) and 5 s (the SDK). The
  `Scan2` runs were not timed.
- `SameInBoth` matched under the first filter. Under `Scan2`, one of its two `rawMethods` entries fails
  the name or path test; which one was not read.
- Three conditions read in the SDK, compared with the source:
  - `AuthUIDelegate`: `(os(iOS) || os(tvOS) || os(visionOS))`, from
    `FirebaseAuth/Sources/Swift/Utilities/AuthUIDelegate.swift:15`.
  - `RecaptchaProviderTesting`: `(os(iOS) && !targetEnvironment(macCatalyst) || os(visionOS))`, from
    `FirebaseAppCheck/Tests/Unit/Swift/RecaptchaProvider+Test.swift:15`.
  - `FederatedAuthProvider.credential(with:)`: `(os(iOS))`, from
    `FirebaseAuth/Sources/Swift/AuthProvider/FederatedAuthProvider.swift:19-30`.
- `grep -rlE '^[[:space:]]*#if'` finds no `.swift` file in `Tests/Checks/Fixtures`,
  `Tests/Checks/PluginFixture` or `Tests/Examples/ExampleProjectSpm/Sources`, and none in
  `modaal-firebase-wrappers` outside `.build`.

The prototype does not handle raw strings (`#"…"#`) or a string interpolation that holds a `"`
(`"\(f("x"))"`): step 1 ends the literal at the inner quote.

---

## 2. The shape this proposes

### 2.1 The script

1. **Stderr in a variable.** Both commands become `err="$(swift build … 2>&1 > /dev/null)"` inside the
   `if`. `:80-81`'s `mktemp` and `trap` are removed. (D1)
2. **`--disable-sandbox`.** `PRINT_MOCKS_DISABLE_SANDBOX=1` adds the flag to both commands. A command run
   without it that fails with `sandbox_apply: Operation not permitted` in its stderr is run again with it,
   after the line `print-mocks: SwiftPM could not start its sandbox; planning again with
   --disable-sandbox` on stderr. (D2)
3. The header comment's environment list (`:20-26`) and `references/printing-mocks.md` §"SwiftPM packages"
   name the variable and the retry.
4. The Xcode lane is unchanged: it creates no temporary file and runs no SwiftPM (§1.1).

**Superseded in part by §11.2 item 1:** step 2's retry also runs on `Plugin ended with exit code 71`.

### 2.2 The plugin

`_createBuildCommands` creates `<pluginWorkDirectory>/.sourceryBuild/tmp` beside the directories it
already creates (`:764-787`) and adds `TMPDIR` = that path to `sharedEnvironmentVars` (`:789`). Both halves
of the plugin build their commands there (§1.3). (D3)

### 2.3 The templates

`templates/Utility/CompilationConditions.swift` is the one file that derives a condition, and all three
entry points include it.

1. **A protocol's condition** is §1.9 step 4's. **A member's** is step 5's, read in the protocol that
   declares it (`definedInType`), so an inherited member carries the condition of its own file.
2. **Pairing a scanned declaration with Sourcery's entry** is decided by D5.
3. **A refusal.** Where the scan and Sourcery cannot be paired, generation fails naming the protocol, the
   file and both counts, as the other refusals do (`MockError`, `MockGenerator.swift:4-26`). Under D4 (b)
   or (d) the message also names the annotation that sets a condition by hand.
4. **Mocks** (`MockGenerator.swift:49-130`). A conditional member's `mockImpl()` lines sit between
   `#if <condition>` and `#endif`. A conditional protocol's lines, from `// MARK: - <Protocol>` to the
   class's closing brace, sit between one pair placed above and below them. A condition of one frame and
   one clause is emitted as the source wrote it; any other is emitted as §1.9 step 2 composes it. For
   DISCOVERY 69's protocol:

   ```swift
   final class AvatarRepositoryProtocolMock: AvatarRepositoryProtocol {
       …
       // MARK: - Methods
       func fetch(id: String) -> String { … }
       …
       #if canImport(UIKit)
       func uploadOwnPhoto(_ image: UIImage) { … }
       var uploadOwnPhotoCallCount: Int = 0
       var uploadOwnPhotoArgs: [UIImage] = []
       …
       #endif
   }
   ```

   `MockNaming` names every member over the whole member list, conditional or not, so a member has the
   same name on every platform. `MockNaming.checkForCollisions` (`:125-127`) is given the declaration
   lines only, without the directive lines.
5. **A conditional property the initializer takes** (`provideValueInInitializer`, `MockVar.swift:27-31`) is
   decided by D7.
6. **Imports** a conditional member needs are decided by D6.
7. **Components** (`ComponentGenerator.swift:155-160`): each forwarder inside its member's `#if`, and the
   class inside its protocol's.
8. **Type erasure** (`TypeErase.swifttemplate:40-122`) is decided by D8.

**Superseded in part by §8.4:** steps 1 to 3. A condition is read from `if` annotations, and no scan is
paired or refused.

### 2.4 The gates

- **Fast lane.** `Tests/Checks/Fixtures/Conditional.swift` declares one protocol per row of §1.9's first
  table, with conditions on `FIXTURE_CONDITION_A` and `FIXTURE_CONDITION_B` so that both sides of each
  `#if` compile on the host. A member under a flag names a type declared only under that flag, which is
  DISCOVERY 69's shape. `run-checks.sh` §6 (`:428-448`) typechecks each language mode three times: with no
  flag, with `-D FIXTURE_CONDITION_A`, and with `-D FIXTURE_CONDITION_B`.
- **Refusals.** `run-checks.sh`'s refusal section gains two red controls: D7's conditional initializer
  property, and a protocol declared in both clauses of an `#if` (`_JSONStringDictionaryDecodableMarker`'s
  shape), each matched on its message.
- **Snapshot.** No existing fixture holds `#if` (§1.9), so `Mocks.generated.swift` and
  `Components.generated.swift` change by the new fixture's blocks only; any other hunk is a defect in the
  phase that produced it.
- **Plugin lane**, `run-plugin-checks.sh` §13. `print-mocks.sh App ProfilePersisting` under
  `sandbox-exec -p` with `deny-temp+items` on a fresh `SCRATCH_PATH`, once with
  `PRINT_MOCKS_DISABLE_SANDBOX=1` and once without, each block equal to the unsandboxed one. It fails on
  row b's line without §2.1 step 1, on row c's without step 2, and on row k's without §2.2.
- **Xcode lane.** After the green project builds, `.sourceryBuild/tmp` exists under `App`'s plugin work
  directory.
- **Skill lane.** SC14 over any `print-mocks:` line the references quote.
- `ci.yml` is unchanged.

**Superseded in part by §8.5:** the fast-lane fixture and the refusal red controls.

**Superseded in part by §11.2 item 2:** the plugin lane's sandboxed print runs three times.

### 2.5 The documents

- `README.md`: the mocks' rule list (`:146`) and the Components' "What it refuses" (`:267`) state that a
  member or protocol inside `#if` is generated inside the same condition, and the refusals of §2.3.
- `CONTRIBUTING.md`: a §"Where to change what" entry for a condition, naming the new file; a §"Pitfalls"
  bullet for §1.5; the three `Type` properties of §1.6 under §"SourceryRuntime API notes"; the fast-lane
  and plugin-lane rows of §"What each artifact covers".
- `Tests/Checks/README.md`: the fixture's table.
- `references/printing-mocks.md`: §2.1's variable and retry. `references/troubleshooting.md`: an entry for
  `cannot find type '<T>' in scope` in a generated file whose protocol declares `<T>` under `#if`, and
  one per refusal message.
- `CHANGELOG.md`: an `Unreleased` entry.

**Superseded in part by §8.2 and §8.6:** the refusals are D7's and §8.4 step 3's, and the troubleshooting
entry names `// sourcery: if = "<the #if condition>"`. `CONTRIBUTING.md`'s §"SourceryRuntime API notes"
takes no `Type` position properties, which D4 (a) alone read.

---

## 3. Decisions

None is ruled. Each lists the option recommended first.

**Superseded by §10.1:** every decision below is ruled.

### D1 — how the script keeps `swift build`'s stderr

- **(a) In a variable (recommended).** No file, so no temporary directory, and `$err` is read where `:85`,
  `:90` and `:95` read the file now (§1.1). Cost: the whole of stderr in memory; `ExampleProjectSpm`'s
  plan was not measured this way.
- **(b) `mktemp "${TMPDIR:-/tmp}/print-mocks.XXXXXXXXXX"`.** Created in `TMPDIR` (§1.1). Keeps the file and
  the `trap`.
- **(c) `mktemp -p "${TMPDIR:-/tmp}"`.** Created in `TMPDIR` (§1.1). The same as (b) with the flag
  spelling.

**Ruled on 2026-09-13 — §10.1:** (a).

### D2 — how `--disable-sandbox` reaches `swift build`

- **(a) A setting, `PRINT_MOCKS_DISABLE_SANDBOX=1`.** The caller decides. Cost: an agent inside a sandbox
  has to know the variable; DISCOVERY 17 measured three or four turns per run spent finding
  `--disable-sandbox` when the prompt did not name it.
- **(b) A retry on `sandbox_apply: Operation not permitted`.** No setting to know. Costs: one failed plan
  first, 1 s in §1.3 row c; the retry keys on SwiftPM's text, which D9 (a)'s sandboxed gate reports if a
  toolchain changes it; SwiftPM's sandbox is turned off without the caller asking, in the case where it
  could not start (§1.2) and under an outer sandbox that still applies (DISCOVERY 18).
- **(c) Both (recommended).** The setting skips the failed plan, and the retry serves a caller that does
  not set it.
- **(d) Neither.** `references/printing-mocks.md` gives the `swift build` command with `--disable-sandbox`
  for an agent that cannot run the script, and the lab keeps `lab/v2/bin/swift`.

**Ruled on 2026-09-13 — §10.1:** (c).

**Superseded in part by §11.2 item 1:** the retry keys on two texts of SwiftPM's.

### D3 — which `TMPDIR` the plugin sets

- **(a) `<pluginWorkDirectory>/.sourceryBuild/tmp` (recommended).** Inside the scratch path, so a profile
  that lets the build write there lets Sourcery write. Set whether or not the caller sets `TMPDIR`. The
  directory the lab's port uses (§1.4). Cost: §1.4's 11 entries stay under `.sourceryBuild/tmp` between
  builds.
- **(b) The plugin process's `TMPDIR`, when set.** Follows the caller (§1.4's first row). Cost: with
  `TMPDIR` unset the prebuild command gets none, as today.
- **(c) None.** An adopter under a profile that denies `<USER_TEMP>` allows row m's paths and more, or
  uses a patched bundle as the lab does.

**Ruled on 2026-09-13 — §10.1:** (a).

### D4 — where a member's condition comes from

- **(a) The source text, §1.9 (recommended).** No adopter edit: DISCOVERY 69's port generates a mock that
  compiles on macOS without deleting the member. Costs: a scanner of about 130 lines in `templates/`
  restating part of Swift's lexical rules, with the gaps §1.9 names; the refusal of §2.3 step 3; the first
  template in `templates/` that reads a source file (`grep` for `FileManager`, `contentsOfFile` and
  `contents(atPath` over `templates/` finds none today).
- **(b) A registry option, `compilationCondition = "<condition>"`,** on a protocol, a method or a property,
  and through `// sourcery:begin:` / `// sourcery:end` around several (§1.7). One record in
  `AnnotationRegistry.swift`, rendered into README and the skill by `Scripts/render-annotations.sh`. Costs:
  each `#if` is written twice, once as the directive and once as the annotation; an edit to one without
  the other fails at the consumer's compile; DISCOVERY 69's port needs an annotation.

  **Ruled on 2026-09-13, and superseded in part:** the spelling is `// sourcery: if = "<condition>"`
  (§7.1); (b) is the ruled option (§8.1); the template shape is §8.4, the gates §8.5, P4 §8.6.
- **(c) The literal key, `/// sourcery: #if canImport(UIKit)`.** It parses as a key that holds the
  condition (§1.7). `AGENTS.md` §"State a rule once" names each verb once, as a record, and a key that
  differs per condition cannot be one: `run-annotation-checks.sh` AC1 fails on it unless it gains an
  exception.
- **(d) (a), and (b) on a declaration that carries it.** The annotation replaces the scanned condition for
  that declaration, and §2.3 step 3's message names it. Costs: both (a)'s and (b)'s.

**Superseded in part by §7:** the spelling `compilationCondition` in (b), which (d) reuses. The annotation
is `if = "<condition>"`. The choice among (a), (b) and (d) stays open.

**Ruled (b) on 2026-09-13 — §8.1.**

### D5 — how scanned declarations pair with Sourcery's entries

- **(a) By declared name, in order; merged declarations joined; checked only where a directive is
  (recommended).** The identifier after each scanned `func` or `var` pairs with the next entry of that
  name in Sourcery's filtered list (`Method.callName`, `Variable.name`). A scanned declaration left over
  whose name matches an entry already paired is a declaration Sourcery merged (§1.5's `SameInBoth`); the
  entry takes the disjunction of both conditions, and a disjunction covering every clause of a frame is
  emitted with no condition. Any other leftover on either side is §2.3 step 3's refusal. A protocol whose
  body and file prefix hold no directive is emitted as today, with no pairing, so none of the 123
  protocols of the fixtures, `ExampleProjectSpm`, `PluginFixture` and `modaal-firebase-wrappers` (§1.9)
  can reach the refusal. Cost: the name pairing is not in the
  prototype; P4 adds it and re-runs every corpus of §1.9.
- **(b) By position, §1.9 step 5, checked only where a directive is.** The prototype as measured. Cost:
  `SameInBoth`, whose mock compiles today with one `render()`, is refused (§1.9, `Scan2`).
- **(c) (a) with the check on every protocol the templates emit.** Cost: a protocol with no `#if` can be
  refused, by a lexical gap of §1.9 or a merge of §1.9's SDK kind; none was measured in the corpora.

**Superseded by §8.2:** D5 pairs a scan with Sourcery's entries, which exists under D4 (a) only.

### D6 — the imports a conditional member needs

`UIImage` resolves only with `import UIKit`, and `args.import: [UIKit]` imports it on every platform,
which fails on macOS with `no such module 'UIKit'` (§1.5).

- **(a) Copy the `#if` blocks that hold only `import` lines (recommended).** From the part of each file
  before its first declaration, for each file that declares an emitted conditional member or protocol,
  once per distinct block, after the header's imports. The generated file imports what the protocol's
  file imports, under the same condition; §1.8 measured an `#if`-wrapped `import` after other
  declarations. Cost: the scanner reads each such file's leading blocks too.
- **(b) `#if canImport(X)` / `import X` / `#endif` for each `canImport(X)` term of an emitted
  condition.** Covers DISCOVERY 69's shape. Cost: a member under `os(iOS)` that uses a UIKit type still
  needs the import from somewhere.
- **(c) None.** The config's `args.import` and the `import` annotation, which serve only a module present
  on every platform the target builds for.

**Superseded in part by §8.2:** (a) reads source files and is withdrawn with D4 (a). (b) and (c) stand,
and the recommendation moves to (b), read from the `canImport(X)` terms of `if` values.

**Ruled on 2026-09-13 — §9.1:** (b), extended to the configured imports, plus the manual item form
`<M> // if canImport`. (c) is not taken.

### D7 — a conditional property the initializer takes

- **(a) Refuse (recommended).** The message names the member and the two ways out: `/// sourcery: handler`
  on the property, which removes it from the initializer (`MockVar.swift:30`), or a property type with a
  default value.
- **(b) One initializer per combination of such conditions**, each inside its `#if`. Cost: up to 2ⁿ
  initializers for `n` independent conditions, and a test that constructs the mock differently per
  platform.

**Ruled on 2026-09-13 — §10.1:** (a), with the scope that row states.

### D8 — type erasure

`TypeErase.swifttemplate` runs in the full lane only (`Tests/Examples/ExampleProjectSpm`,
`SwiftSourceryTemplatesTypeErasureSpec.swift`); the fast lane's `TEMPLATES` (`run-checks.sh:54-57`) lists
`Mocks` and `Component`.

- **(a) Wrap (recommended).** Each member of `_Any<P>Base`, `_Any<P>Box` and `Any<P>` inside its `#if`,
  and the three classes inside the protocol's. The emission is the same per-member rule as §2.3 step 4.
  Cost: a conditional protocol in `ExampleProjectSpm/Sources/ExampleProjectSpm/Protocols/Protocols.swift`
  and `test-ios.sh` before the branch merges.
- **(b) Refuse** a conditional member or protocol, naming it. Cost: the same full-lane fixture, for the
  refusal; a type-erased protocol with an `#if` member gets no wrapper.

**Ruled on 2026-09-13 — §10.1:** (a).

### D9 — the gate

- **(a) §2.4 as written (recommended).**
- **(b) (a) without the plugin lane's sandboxed run.** For a `macos-15` runner on which `sandbox-exec` is
  missing or behaves differently (§5). The script and plugin changes are then run only unsandboxed, where
  row a passes with or without them.
- **(c) (a) with a behaviour check under `-D FIXTURE_CONDITION_A`**: `Tests/Checks/Behaviour/Main.swift`
  compiled a second time, calling one conditional member and reading its counter.

**Ruled on 2026-09-13 — §10.1:** (a).

### D10 — the skill and the eval suite

- **(a) The two references only (recommended).** `SKILL.md` (211 lines, ~4.9k tokens on invoke, 005 §8.4)
  and `Tests/Evals/` are unchanged.
- **(b) (a), plus an eighth eval case**: a protocol with a member inside `#if canImport(UIKit)`, asking
  whether its mock compiles on macOS. Cost: the right answer depends on the installed release, and SC9
  forbids naming a version in the tree.

**Ruled on 2026-09-13 — §10.1:** (a), with the scope that row states.

---

## 4. Phasing

All on `spec/006-sandboxed-print-and-conditional-members`, after the rulings; each phase one commit with the
prefix `[006-sandboxed-print-and-conditional-members]`.

**Read with §7 and §8:** D4 is ruled (b) with the `if` spelling, so P4 and P7 follow the pointers under
them, and D5 and D6 (a) are withdrawn (§8.2).

**Read with §9:** D6 is ruled there, and P4 and P7 also carry §9.4 to §9.6.

**Read with §10:** the remaining decisions are ruled there, and `args.testable` joins §9.3's grammar
(§10.2).

- **P1** — the plugin's `TMPDIR` (D3). `run-plugin-checks.sh` and `run-xcode-checks.sh` green, with the
  Xcode lane's `.sourceryBuild/tmp` assertion.
- **P2** — the script (D1, D2) and `references/printing-mocks.md`. §1.3's rows b to m re-run with it and
  the P1 plugin, and recorded in the commit message. 005 §2.2 takes a line pointing to this spec's §2.1.
- **P3** — the plugin lane's sandboxed print (D9). Its first `ci.yml` run on `macos-15` is recorded once
  the branch is pushed.
- **P4** — `templates/Utility/CompilationConditions.swift` from the prototype with D5's pairing, the Mocks
  emission, D6's imports, D7's refusal, `Fixtures/Conditional.swift` with `ProtocolMock`, the typecheck
  invocations and the two red controls. §1.9's corpora re-run and recorded. The snapshot diff read, then
  recorded.

  **Superseded by §8.6:** P4 carries the `if` record (§7.1), §8.4's shape and §8.5's fixture and red
  controls; there is no prototype port and no corpus re-run.
- **P5** — the Components emission, and `DuetComponent` on the fixture's protocols. The snapshot diff read,
  then recorded.
- **P6** — type erasure (D8) and its full-lane fixture. `test-ios.sh` green.
- **P7** — `README.md`, `CONTRIBUTING.md`, `Tests/Checks/README.md`, `references/troubleshooting.md` (D10),
  the `Unreleased` `CHANGELOG.md` entry; under D4 (b) or (d), `Scripts/render-annotations.sh` run and its
  output read. `run-skill-checks.sh` and `run-annotation-checks.sh` green.

  **Superseded in part by §7.3 and §8.2:** `Scripts/render-annotations.sh` runs and its output is read
  without the D4 condition. The troubleshooting entry names `// sourcery: if = "<the #if condition>"`
  (§8.6).
- **P8** — this spec takes a section recording what landed and what was measured on the way.

Then the pull request, and after it merges, **R** on `master`, following `CONTRIBUTING.md` §"Cutting a
release": the seven lanes green; `modaal-firebase-wrappers` regenerated against `master` and the size of
its diff recorded in the `CHANGELOG.md` entry — §1.9 found no `#if` in its sources and no condition in its
34 protocols; the `templates-X.Y.Z` tag, the pin commit, the bare `X.Y.Z` tag, and the by-URL example job.
R's record is an addition to this spec on `master`.

The lab copies the skill from an upstream commit and records `skill_sha256` (lab spec 002 §5.2), so it can
take P2's script from the merge commit. It takes P1's plugin with R's release.

**Superseded in part by §8.6:** P4.

---

## 5. Not measured

- `sandbox-exec` on GitHub's `macos-15` runners, and `ci.yml`'s Xcode 26.3. Every row of §1 ran on Xcode
  26.6.
- The Xcode half of the plugin with either `TMPDIR` patch, and an `xcodebuild` build under an outer
  sandbox.
- The lab's round-5 profile (`lab/v2/sandbox-profile.sh`) with this spec's script and plugin and without
  `lab/v2/bin/`. DISCOVERY 74 records the lab's Swift print check passing 79 of 79 under that profile, which
  denies `<USER_TEMP>` and allows back only `xcrun_db` (`:51-54`, `:70`). Whether that tree's scratch path
  was planned before the profile applied, and so needed no write under `<USER_TEMP>/TemporaryItems`, was
  not read.
- Which SwiftPM call writes under `<USER_TEMP>/TemporaryItems`. §1.3 measured that allowing it clears rows
  d and i, and that the runs allowing it added one entry there.
- `print-mocks.sh` with D1 (a) on a plan whose stderr is long, such as `ExampleProjectSpm` planned for the
  iOS simulator.
- Which of `SameInBoth`'s two `rawMethods` entries fails `Scan2`'s filter, and why.
- A protocol extension annotated `ProtocolMock` — the RIBs external-annotation pattern the full lane
  covers — whose members the scanner would read from another type's body.
- Raw strings and string interpolations holding `"` inside a protocol body (§1.9).
- Sourcery's `master` branch, for an `#if` condition exposed after tag 2.3.0.
- An Intel Mac.

**Superseded in part by §8.2:** the bullets on `SameInBoth` under `Scan2`, the RIBs extension, and raw
strings concern D4 (a) only.

---

## 6. Open questions

1. Whether `references/printing-mocks.md` states that a print inside an outer sandbox also needs
   `<USER_TEMP>/TemporaryItems` writable (§1.3). No file in this repository controls that write.
2. Whether R's release is a minor or a patch. The generated output changes only for a protocol that
   declares `#if`, and every such protocol failed to compile on some platform before (§1.5).

**Superseded by §10.3.**

---

## 7. The ruling of 2026-09-13 on the annotation's spelling

Supersedes D4 (b)'s spelling `compilationCondition`, which D4 (d) reuses. D4 is not ruled: whether a
condition comes from the source text, from the annotation, or from both stays open.

### 7.1 The ruling

The annotation D4 (b) and (d) describe is written

```swift
// sourcery: if = "canImport(UIKit)"
// sourcery: if = "os(iOS)"
// sourcery: if = "compiler(>=6.0)"
```

The value is the text that follows `#if` in the directive the annotation stands for. It is one option
record in `templates/Annotations/AnnotationRegistry.swift`. Its `name` is a Swift keyword and its
`static let` is not, as in the `init` and `import` records (`:151-152`, `:169-170`):

```swift
static let ifCondition = Annotation(
    name: "if",
    aliases: [],
    kind: .option,
    target: "Protocol / method / variable",
    effect: "Generate the member, or the whole mock, inside `#if <value>`",
    valueHint: "canImport(UIKit)"
)
```

`if` matches AC7's option pattern `^[a-z][A-Za-z]*$` (`Tests/Checks/run-annotation-checks.sh:312`).

### 7.2 Measured

On 2026-09-13, on the machine and Sourcery 2.3.0 of §1, through dump templates in the session scratchpad:

| source | what Sourcery attaches |
| --- | --- |
| `// sourcery: if = "canImport(UIKit)"` above `// sourcery: ProtocolMock`, on a protocol | the protocol: `["if": canImport(UIKit), "ProtocolMock": 1]` |
| `// sourcery: if = "canImport(UIKit)"` on a method | `["if": canImport(UIKit)]`, a string |
| `// sourcery: if = "os(iOS)"` on a method | `["if": os(iOS)]`, a string |
| `// sourcery: if = "compiler(>=6.0)"` on a method | `["if": compiler(>=6.0)]`, a string |
| `/// sourcery: if = "canImport(UIKit)"` on a method | `["if": canImport(UIKit)]` |
| `// sourcery:begin: if = "canImport(UIKit) && !os(watchOS)"` … `// sourcery:end` around a method and a property | each of the two: `["if": canImport(UIKit) && !os(watchOS)]` |
| the three lines of §7.1 stacked above one method | `["if": [compiler(>=6.0), os(iOS), canImport(UIKit)]]`, an array in reverse source order |
| `/// sourcery: canImport = "UIKit"` on a method | `["canImport": UIKit]`; parsed, and not the ruled spelling |

### 7.3 What the shape becomes

- Several `if` values on one declaration are joined with `&&`, each in parentheses.
  `annotations(for:)` returns the values de-duplicated and sorted (`AnnotationAccess.swift:27-38`), so the
  emitted condition is the same text for any order of the source lines.
- A value on `// sourcery:begin:` applies to each declaration up to `// sourcery:end` (§7.2).
- Under D4 (b) or (d), §2.3 step 3's refusal message names `// sourcery: if = "<condition>"`.
- Under D4 (b) or (d), the record lands in P4 with the template code that reads it:
  `run-annotation-checks.sh` AC3 fails on a record no template reads. P7's
  `Scripts/render-annotations.sh` run renders its row into `README.md`,
  `skills/swift-sourcery-mocks/SKILL.md` and `references/writing-testable-protocols.md`.

**Superseded in part by §8.1:** "D4 is not ruled" in §7's opening paragraph, and "Under D4 (b) or (d)" in
§7.3, which now holds without the condition.

**Superseded in part by §11.2 item 9:** `Scripts/render-annotations.sh` runs in P4.

---

## 8. The ruling of 2026-09-13 on D4

### 8.1 The ruling

**D4 (b)**, with §7.1's spelling. A declaration's condition comes from its `// sourcery: if = "<condition>"`
annotations only, and no template reads a source file. The reason given with the ruling: reading Swift
source text with a hand-written scanner is unreliable — §1.9 names two lexical gaps, and D5 was needed to
pair the scan with Sourcery — and it would be the first feature in `templates/` that reads source files.

A member or protocol inside `#if` that carries no `if` annotation is emitted with no condition, as 0.9.0
emits it (§1.5). A directive and an annotation that disagree are reported by the consumer's compile; no
template compares them.

### 8.2 What changes elsewhere

| part | under D4 (b) |
| --- | --- |
| §1.9, `Scan.swifttemplate`, `Scan2.swifttemplate` | the record of what D4 (a) measured; nothing of it is built |
| §2.3 steps 1 to 3 | replaced by §8.4 |
| D5 | withdrawn: there is no scan to pair |
| D6 (a) | withdrawn: it reads source files. (b) and (c) stand; (b) is recommended, applied to the `canImport(X)` terms of `if` values |
| D1 to D3, D7 to D10 | unchanged |
| §2.4 | the fixture and the red controls follow §8.5 |
| §4 P4 | follows §8.6 |
| §5 | the bullets on `SameInBoth` under `Scan2`, the RIBs extension and raw strings concern D4 (a) only |
| scope | `templates/Annotations/AnnotationRegistry.swift` and the tables `Scripts/render-annotations.sh` renders are in scope without condition |

**Superseded in part by §9:** the D6 row. D6 is ruled, and `_header.swifttemplate` joins the scope.

### 8.3 Measured

On 2026-09-13, with the machine and Sourcery 2.3.0 of §1:

| source | result |
| --- | --- |
| `ifprobe3`: `var mode: Int` under `#if FIXTURE_FLAG`, `var mode: String` under `#else`, no annotation | Sourcery keeps both in `rawVariables` and `allVariables` (§1.5). Today's `DifferentVarMock` declares `var mode: Int`, `modeGetCount`, `modeGetHandler` and `_mode` once, and nothing for the `String` declaration. Which step of `MockVar.from` (`MockVar.swift:17-20`) drops it was not read |
| `ifkey3`: `func render() -> Int` under `#if os(iOS)` with `// sourcery: if = "os(iOS)"`, and the same declaration under `#else` with `// sourcery: if = "!os(iOS)"` | `rawMethods` holds both, each with its own `if`. `allMethods` holds one, carrying `["if": os(iOS)]` |

### 8.4 The shape of §2.3 steps 1 to 3, under D4 (b)

`templates/Utility/CompilationConditions.swift` stays the one file that turns annotations into a
condition, and all three entry points include it.

1. **A declaration's condition** is its `if` values, each in parentheses, joined with `&&` (§7.3). A
   protocol's condition surrounds the whole mock; a member's surrounds its lines. An inherited member
   carries the annotations of its own declaration, because it is the same object as the declaring
   protocol's `rawMethods` entry (§1.6).
2. **A member Sourcery merged** (§8.3's second row). Its condition joins, with `||`, the conditions of
   every entry of the declaring protocol's `rawMethods` or `rawVariables` that `uniqueMethodFilter` or
   `uniqueVariableFilter` (`Type.swift:107-109`) folds into it. If one of those entries carries no `if`,
   the member is emitted with no condition.
3. **One name declared with two types** (§8.3's first row). When each declaration carries an `if` and the
   two values differ as text, `MockVar.from` keeps both, and both are emitted inside their conditions with
   the same member names. `MockNaming.checkForCollisions` (`MockGenerator.swift:125-127`) accepts that
   repeat only; every other repeated name is refused as it is today. Two conditions true on one platform
   are reported by the compiler.
4. Steps 4 to 8 of §2.3 stand. There is no refusal for a scan; D7's refusal stays.

**Superseded in part by §11.2 items 5 and 6:** step 1's member condition, and step 3's accepted repeat.

### 8.5 The gates, under D4 (b)

- `Tests/Checks/Fixtures/Conditional.swift` has one declaration per shape of §8.4: a member with one `if`;
  a member with stacked `if` lines; `// sourcery:begin:` / `// sourcery:end` around two members; a whole
  protocol; a member inherited from a protocol in another fixture file; §8.3's merged member; §8.3's one
  name with two types. Each also sits inside the matching `#if FIXTURE_CONDITION_A` or
  `#if FIXTURE_CONDITION_B`, so the six typechecks of §2.4 fail when an emission is missing or wrong.
- The red controls are D7's refusal and a repeated name that §8.4 step 3 does not accept. §2.4's red
  control for a protocol declared in both clauses of an `#if` is withdrawn.
- `run-annotation-checks.sh` green with the `if` record and its read (AC1, AC3).

### 8.6 P4, under D4 (b)

- **P4** — `templates/Utility/CompilationConditions.swift` per §8.4, the `if` record (§7.1), the Mocks
  emission, D6's imports as ruled, D7's refusal, the fixture and red controls of §8.5, and the typecheck
  invocations. The snapshot diff read, then recorded. There is no prototype to port and no corpus to
  re-run.
- `references/troubleshooting.md`'s entry of §2.5, for `cannot find type '<T>' in scope` in a generated
  file, tells the reader to put `// sourcery: if = "<the #if condition>"` on the declaration. It lands in
  P7.

**Superseded in part by §9.6:** P4's "D6's imports as ruled" is §9.3's rule and §9.4's fixture rows.

---

## 9. The ruling of 2026-09-13 on D6

### 9.1 The ruling

Two arms, both producing

```swift
#if canImport(UIKit)
import UIKit
#endif
```

- **Automatic** — D6 (b), extended to the configured imports. Each `canImport(<M>)` term in an `if`
  annotation of an emitted protocol or member guards `<M>`: an `args.import` item `<M>` is emitted only
  in the guarded form, and a guarded import is added when `args.import` does not list `<M>`.
- **Manual** — an `args.import` item written `<M> // if canImport` is emitted in the guarded form,
  whatever the annotations say:

  ```yaml
  args:
    import:
      - SwiftUI
      - UIKit // if canImport
  ```

The manual form is chosen so that a release before this spec reads the item as `import UIKit // if
canImport`, which Swift accepts as an unconditional import followed by a comment (§9.2). YAML starts a
comment at `#`, not at `//`, so the whole text is the item's value.

Two forms were considered and not ruled:

- **An object item**, `- module: UIKit` with `if: "canImport(UIKit)"`. Ruled out as too breaking: the
  0.9.0 header emits no import at all for a list holding one (§9.2).
- **Every import wrapped in `#if canImport(<M>)`.** Not ruled.

### 9.2 Measured

On 2026-09-13, with the machine and Sourcery 2.3.0 of §1, and the 0.9.0 `_header.swifttemplate` of this
checkout unless the row says otherwise:

| path | input | `argument["import"]` and the emitted imports | result |
| --- | --- | --- | --- |
| `sourcery --config` | `- Foundation`, `- Combine // if canImport` | `["Foundation", "Combine // if canImport"]`, a `[String]`; `import Combine // if canImport`, `import Foundation` | typecheck with the source: exit 0, 0 diagnostics, under `-swift-version 5 -strict-concurrency=complete` and `-swift-version 6` |
| `sourcery --args` | `"import=Combine // if canImport"` | the string `Combine // if canImport` | — |
| `sourcery --args` | `"import=Foundation,import=Combine // if canImport"` | `[Foundation] [Combine // if canImport]`; `import Combine // if canImport`, `import Foundation` | typecheck `-swift-version 6`: exit 0, 0 diagnostics |
| plugin, `e2e` | `- Foundation // if canImport` | the synthesized config keeps the line as written, below the inserted `testable: [Feature]`; `import Foundation // if canImport`, `@testable import Feature` | `swift build --build-tests` exit 0 in 16 s, 0 errors; `swift test` exit 0 |
| `sourcery --config` | `- SwiftUI`, then `- module: UIKit` / `if: "canImport(UIKit)"`, then `- module: AppKit` / `if: "!os(iOS) && canImport(AppKit)"` | an `NSArray` of a string and two dictionaries, `{if = "canImport(UIKit)"; module = UIKit;}`; `as? [String]` is `nil`; no `import` line emitted, `SwiftUI` included | — |
| plugin, `e2e` | `- Foundation`, then `- module: UIKit` / `if: "canImport(UIKit)"` | the synthesized config keeps both items; the generated file's only import is `@testable import Feature` | print exit 0 |
| `swiftc -typecheck` | a file holding `import if canImport UIKit` | — | `error: expected identifier in import declaration` |
| both fast-lane snapshots with every `import` wrapped by hand in `#if canImport(<M>)`, typechecked with `Tests/Checks/Fixtures` | — | 4 lines added per file (2 imports each) | exit 0, 0 diagnostics in both language modes |
| `e2e-builddir` with its `_header.swifttemplate` patched to wrap `import` and `@testable import` | `- Foundation` | `#if canImport(Foundation)` / `import Foundation` / `#endif`, `#if canImport(Feature)` / `@testable import Feature` / `#endif` | `swift build --build-tests` exit 0 in 18 s, 0 errors; `swift test` exit 0, 1 test |

- `extractImports` (`_header.swifttemplate:18-26`) takes the value `as? String`, else `as? [String]`, else
  returns `[]`, which is why the object item empties the whole list.
- The 21 `*sourcery*.yml` files of this repository (`find -iname`, `.build` and `.git` excluded) hold no
  `import:` item containing `//` or `#`. `modaal-firebase-wrappers` has no such file: its 7 generated files
  come from `--args`, and hold 15 import lines — 7 `import Foundation`, 1 `import UIKit` and 7
  `@testable import`.

### 9.3 The rule

In `templates/Utility/CompilationConditions.swift`, read by `_header.swifttemplate` (`:28-33`):

1. **An item's module** is its text up to the first `//`, trimmed. The item is **manual** when the text
   after `//`, trimmed, is exactly `if canImport`.
2. **An annotated module** is `<M>` in every `canImport(<M>` term, negated or not, of every `if` value on
   the types the template emits and their members. `<M>` runs to the first `,`, `)` or space.
3. **Emission.** Imports are sorted by module. A module that is manual or annotated is emitted once,
   guarded; every other item is emitted as today, its full text after `import `. An annotated module that
   `args.import` does not list is added, guarded.
4. **Where the grammar applies.** `args.import` items, from a config or from
   `--args "import=<M> // if canImport"`, which reaches `extractImports` as the same text (§9.2).
   `args.testable` and the `import` annotation (`AnnotationRegistry.importModule`, emitted by
   `generateAdditionalImports`) keep today's emission (§9.5).

**Superseded in part by §10.2:** `args.testable` takes the grammar of steps 1 to 3.

**Superseded in part by §11.2 item 4:** where `_header.swifttemplate` reads the protocols it guards imports for.

A configuration with no manual item, used with sources that carry no `if` annotation, produces the same
bytes as 0.9.0.

### 9.4 The gates

- **Fast lane, snapshot.** One fixture member of §8.5 carries `// sourcery: if = "canImport(Combine)"`.
  `run-checks.sh` passes `--args "import=Combine,import=Foundation"` (`:79`), so `Mocks.generated.swift`
  shows `import Combine` guarded and `import Foundation` unchanged. §2.4's statement that the snapshot
  changes by the new fixture's blocks only gains this import hunk.
- **Fast lane, manual form.** A generation over scratch sources written by the script, as the near-miss
  section writes its own (`run-checks.sh:188-205`), with
  `--args "import=Foundation // if canImport"` and no `if` annotation, asserting the three guarded lines
  and no other import line.
- **Fast lane, unchanged output.** The zero-match generation (`run-checks.sh:132-135`) has no `if`
  annotation and no manual item, and its snapshot stays byte-identical.
- **Plugin lane.** One config of `Tests/Checks/PluginFixture` lists an item `Foundation // if canImport`,
  and the generated file carries the guarded form.

### 9.5 Open

1. Whether `@testable import` lines take the manual form. §9.2's patched-header row compiled
   `#if canImport(Feature)` around `@testable import Feature`; neither arm of §9.1 names `args.testable`.
2. Whether an item with `//` followed by any other text is emitted as today, comment included, as §9.3
   step 3 proposes, or refused naming the item. §9.2 found no such item in reach.
3. The Xcode half of the plugin with either arm.

**Ruled on 2026-09-13 — §10.2.**

### 9.6 What the phases carry

- **P4** carries §9.3 in `CompilationConditions.swift` and `_header.swifttemplate`, and §9.4's fast-lane
  gates, and the plugin-lane config of §9.4, which generates the guarded form only once the header
  change is in.
- **P7** carries the documents:
  - `README.md` §"Template arguments" (`:673`, the `import=Module` row at `:679`) and §"The options that
    stay yours" (`:471`): the manual form, and the automatic guard from `if`.
  - `references/spm-plugin.md` (`:145-156`) and `references/cli-lane.md`: the manual form.
  - `references/troubleshooting.md`: `no such module '<M>'` in a generated file. Write `<M> // if
    canImport` in `args.import`, or `if = "canImport(<M>)"` on the declaration that uses `<M>`.
  - `CHANGELOG.md`: a config holding a manual item is read by a release before this one as an
    unconditional import (§9.2).

---

## 10. The rulings of 2026-09-13 on D1 to D3, D7 to D10, §9.5 and §6

The owner ruled §9.5 item 1 on 2026-09-13: `args.testable` takes the manual form. In the same message the
owner asked for the remaining open decisions to be resolved as the implementer judged, and for the
implementation to start. Each ruling below is the option §3 recommends, unless the row says otherwise.

### 10.1 The decisions

| decision | ruled | the phase that carries it |
| --- | --- | --- |
| D1 | (a): `swift build`'s stderr in a variable; `print-mocks.sh:80-81`'s `mktemp` and `trap` removed | P2 |
| D2 | (c): `PRINT_MOCKS_DISABLE_SANDBOX=1` adds `--disable-sandbox`, and a plan that fails with `sandbox_apply: Operation not permitted` is run again with it | P2 |
| D3 | (a): `TMPDIR` = `<pluginWorkDirectory>/.sourceryBuild/tmp`, set whether or not the caller sets `TMPDIR` | P1 |
| D7 | (a): a property with its own `if` condition that the initializer takes is refused, naming the member, `/// sourcery: handler` and a property type with a default value. A property of a protocol whose whole mock is conditional is not refused: its initializer sits inside the same `#if` | P4 |
| D8 | (a): type erasure wraps each member and the three classes | P6 |
| D9 | (a): §2.4, as amended by §8.5 and §9.4 | P1, P3, P4, P5 |
| D10 | (a): `references/printing-mocks.md` and `references/troubleshooting.md`, with §9.6's `spm-plugin.md` and `cli-lane.md`. `SKILL.md` changes only inside the block `Scripts/render-annotations.sh` renders (§7.3); `Tests/Evals/` is unchanged | P7 |

### 10.2 §9.5

1. **`@testable import`.** An `args.testable` item written `<M> // if canImport` is emitted as
   `#if canImport(<M>)` / `@testable import <M>` / `#endif`. The automatic arm applies to `args.testable`
   too: a module named by a `canImport(<M>)` term and listed in `args.testable` is emitted in that guarded
   form. §9.3 step 3's added guarded `import <M>` is added only when neither `args.import` nor
   `args.testable` lists `<M>`. An unconditional `@testable import <M>` fails where `<M>` is absent, as
   `import <M>` does (§1.5, the last bullet).
2. **Any other text after `//`** is emitted as today: `import <the item's full text>`. Refusing it would
   fail a configuration that 0.9.0 generates from; §9.2 found no such item.
3. **The Xcode half.** Both halves of the plugin build their commands in `_createBuildCommands` (§1.3),
   and the header reads the synthesized config's `args` in both. P1's Xcode-lane assertion covers D3 there.
   No Xcode-lane gate is added for the import forms.

**Supersedes in part §9.3 step 4:** `args.testable` follows the grammar of §9.3 steps 1 to 3, as item 1
says.

### 10.3 §6

1. `references/printing-mocks.md` states that a print under an outer sandbox needs write access to
   `<USER_TEMP>/TemporaryItems`, which SwiftPM writes and neither the script nor the plugin controls (§1.3
   row k). It lands in P2.
2. R is a minor release, `0.10.0`: it adds the `if` annotation and the `// if canImport` item form. The
   output changes only for a protocol or member carrying `if` and for a configuration holding a manual
   item (§9.3). R's push, pull request, merge and tags each still need their own go-ahead.

**Supersedes:** §6 items 1 and 2, and "None is ruled" in §3's opening line.

---

## 11. What landed, 2026-09-13

Every measurement below was taken on 2026-09-13 on the machine, Xcode, Swift and Sourcery of §1. Nothing is
pushed: `ci.yml` has not run on the branch.

### 11.1 The commits

| phase | commit | what |
| --- | --- | --- |
| rulings | `6c4fbfd` | §9 and §10 |
| P1 | `056691d` | the plugin's `TMPDIR` under `.sourceryBuild/tmp`; the Xcode lane's assertion |
| P2 | `bda7bd2` | `print-mocks.sh`: stderr in a variable, `PRINT_MOCKS_DISABLE_SANDBOX`, the retry; `references/printing-mocks.md`; 005 §2.2's pointer; SC14 reads `note "…"` |
| P3 | `19e3150` | the plugin lane's sandboxed print |
| P2, P3 | `ca81570` | the retry also on `Plugin ended with exit code 71`; the gate plans a fresh path and then the same path again |
| P4 | `856b235` | `CompilationConditions.swift`, the `if` record, the Mocks emission, D7's refusal, the import rule, the fixtures and gates, the rendered tables |
| P5 | `ef6c9d7` | the Components emission; `uniqueByName`; `DuetComponent` on the conditional fixtures |
| P6 | `da673ca` | type erasure; `ConditionalErasable` and `MacOnlyErasable` in `ExampleProjectSpm` |
| P7 | `479ce57` | README, CONTRIBUTING, `Tests/Checks/README.md`, the three skill references, CHANGELOG |
| P8 | `3d3b9c8`, and the commit that adds this section | `3d3b9c8` holds the forward pointers only. Its message describes this section, which a failed step of the command that made it left out |

### 11.2 Where the implementation differs from §2 to §10

1. **The retry key (§2.1 step 2, D2).** SwiftPM caches a manifest by the path it planned it under. On a
   path it has planned before, the first sandbox it starts inside an outer one is the plugin's, and the
   plan fails with `error: Plugin ended with exit code 71` and no `sandbox_apply` text. `bda7bd2` retried
   on `sandbox_apply` only; `ca81570` retries on either text. Measured in `PluginFixture` under
   `deny-temp+items`, `PRINT_MOCKS_DISABLE_SANDBOX` unset:

   | scratch path | script | exit | real | stderr |
   | --- | --- | --- | --- | --- |
   | not planned before, twice | `bda7bd2` | 0 | 40 s | the retry note |
   | planned before, kept | `bda7bd2` | 1 | 0 s | `Plugin ended with exit code 71`, `print-mocks: planning App failed` |
   | planned before, deleted and recreated | `bda7bd2` | 1 | 3 s | the same |
   | planned before, kept | `ca81570` | 0 | 35 s | the retry note; the 50-line block |

   The second print an agent makes in one package, inside its sandbox and without the setting, takes the
   planned path. The script does not print the first plan's stderr once the retry succeeds, so the gate
   asserts the note and the block, not SwiftPM's text.
2. **The gate (§2.4, plugin lane).** `run-plugin-checks.sh` §13 runs the sandboxed print three times: with
   the setting; without it on a scratch path unique to the lane run; and without it on that path again.
   A plugin-lane run during P4 failed its sandboxed gate because P3's gate reused one path between lane
   runs.
3. **SC14.** `print-mocks.sh` prints the retry line through a `note` helper, and
   `run-skill-checks.sh` SC14 reads `note "…"` strings as well as `fail "…"`. SC14 had read `fail "…"`
   only, and failed on the quoted retry line.
4. **Where the imports are emitted (§9.3, §9.6).** `_header.swifttemplate` keeps the import lines as
   template text and reads `importSelectors`, which each entry point declares above its
   `include("_header")`. A header function that `print`ed them wrote the imports above all template text:
   every generated file differed from its snapshot at line 4.
5. **A protocol's `if` and its members (§8.4 step 1).** A dump over `/// sourcery: if =
   "FIXTURE_CONDITION_A"` on a protocol showed no `if` on its members, so a member's condition is its own
   values; nothing is subtracted.
6. **The accepted repeat (§8.4 step 3).** `MockNaming.checkForCollisions` receives the directive lines
   and accepts a repeated property name whose every declaration sits inside a condition different from
   each other's. That covers §8.4 step 3's case and any other pair of distinct conditions; a repeat with
   no condition on one side, or the same condition on both, is refused as before. The
   `conditionalcollision` red control is the first kind.
7. **`uniqueByName` (P5).** The rule that keeps both properties of step 3 lives in
   `CompilationConditions.uniqueByName`, which `MockVar.from` and `ComponentGenerator.forwardedVariables`
   both call.
8. **`generateAdditionalImports`** compares the modules of `args.import` items, and the modules an `if`
   value guards, with the `import` annotation's values, so an `import` annotation does not add an
   unguarded import of a guarded module.
9. **The rendered tables (§7.3).** `Scripts/render-annotations.sh --write` ran in P4:
   `run-annotation-checks.sh` AC6 fails from the commit that adds a record until the tables are rendered.
10. **P1's `TMPDIR`** is in `sharedEnvironmentVars`, which `SourceryConfigSynthesizer.expandEnvironment`
    (`SourcerySwiftCodegenPlugin.swift:684-690`) also reads to expand a `${NAME}` in a config, so a config
    naming `${TMPDIR}` receives `.sourceryBuild/tmp`. Read from the code, not measured.
11. **Type erasure and `{ get set }`.** `_Any<P>Box` assigns `concrete.<name> = newValue` on a
    `private let concrete`, so a `{ get set }` property of a protocol that is not class-bound does not
    compile (`cannot assign to property: 'concrete' is a 'let' constant`), with or without a condition.
    `ConditionalErasable.label` is `{ get }`. The template is unchanged there.
12. **P3's red controls.** The script before this spec failed on `mktemp: mkstemp failed` and the script
    without its retry on `sandbox_apply: Operation not permitted`, each under the gate's profile. The
    plugin without P1 was not re-run; §1.3 row k records it.

**Superseded in part by this section:** §2.1 step 2 and D2 (c)'s retry text (item 1); §2.4's plugin-lane
gate (item 2); §8.4 steps 1 and 3 (items 5 and 6); §7.3's P7 rendering (item 9); §9.3's "read by
`_header.swifttemplate`" (item 4).

### 11.3 Measured on the way

- **Byte-identical output.** P4's templates over the fixtures of `19e3150` and over the zero-match source
  produced all four snapshots byte for byte; P6's `TypeErase.swifttemplate` over
  `Tests/Examples/ExampleProjectSpm/Sources/ExampleProjectSpm` produced the 184 lines of `19e3150`'s,
  byte for byte, before `ConditionalErasable` was added.
- **Snapshot diffs, read before recording.** P4: `Mocks.generated.swift` 254 lines added, none removed —
  `#if canImport(Combine)` / `#endif` around `import Combine`, and seven mocks. P5:
  `Components.generated.swift` 123 lines added, none removed — the same guard, and seven Components;
  `Mocks.generated.swift` unchanged.
- **Typechecks.** Six per fast-lane run — both language modes, with no flag, `-D FIXTURE_CONDITION_A` and
  `-D FIXTURE_CONDITION_B` — 0 diagnostics from P4 on.
- **Type erasure red control.** The erasure of `ConditionalErasable` and `MacOnlyErasable` with its
  `#if` lines removed, typechecked for `arm64-apple-ios17.0-simulator`: `error: no such module 'AppKit'`.
  With them: 0 diagnostics for the simulator and for macOS.
- **The sandboxed rows of §1.3,** re-run with P2's script and P1's plugin: `bda7bd2`'s message.
- **The full lane:** `Tests/Examples/ExampleProjectSpm/test-ios.sh` at `da673ca`: Test Succeeded, 20 tests, 0 failures; the `TypeErase.generated.swift` it compiled holds both erasures inside their `#if` lines.

### 11.4 Not done

- `ci.yml` on the branch, including the sandboxed gate on `macos-15` (§5). The branch is not pushed.
- R: the release, `modaal-firebase-wrappers` regenerated, the tags.
- The lab's round-5 profile with this branch's script and plugin (§5).
- D9 (c)'s behaviour check under `-D FIXTURE_CONDITION_A`; D9 is ruled (a).
