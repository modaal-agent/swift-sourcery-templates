# 001 follow-up — The Xcode path: what it derives, the discovery bug, and a check lane built with XcodeGen

**Status:** Proposed, not implemented. Written 2026-09-10.

**Measurements:** every number and quoted string in §1 was produced on 2026-09-10 against `master` at
`39a56d9`, with Xcode 26.5 (build 17F42), XcodeGen 2.44.1 and Sourcery 2.3.0, using a throwaway
XcodeGen project and a throwaway probe plugin written into a scratch directory outside this
repository. Nothing in the repository was changed to take them.

**Scope:** `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`, `Tests/Checks/`,
`.github/workflows/ci.yml`, `README.md`. No template change. No change to `mock-templates`.

**Obsoletes:** 001 §3.4, the clause "plus the `.product` module directories already reachable at
`:287-292`" — measured false in §1.3 below. **Answers:** 001 §11.2, both threads. **Follows:** 001 §8
step 6, which shipped the degradation and deferred the exploration.

---

## 0. TL;DR

1. The Xcode path works end to end today: the config is discovered, synthesized with `output:`
   supplied, Sourcery runs, and Xcode compiles the generated file into the target (§1.2).
2. `XcodeTarget.dependencies` returns an empty array — for a package product dependency **and** for a
   sibling Xcode target dependency, with both declared in `project.pbxproj` (§1.3). The `.product`
   branch at `SourcerySwiftCodegenPlugin.swift:1039-1045` never runs. `${SOURCERY_SOURCES}` in an
   Xcode project expands to the target's own input-file directories and nothing else.
3. A target that depends on a sibling Xcode target fails the build (§1.4). The linked framework
   arrives in `inputFiles` as `<project>/build/Debug/Core.framework`, `sourceryConfigFileLocations`
   (`:1055-1071`) derives `<project>/build` from it, that directory does not exist, and `:652`
   reports the enumeration failure as `Diagnostics.error`, which fails the build. One code fix, §3.
4. The closure rule for Xcode stays as measured, and the author names the remaining directories by
   hand with `${SOURCERY_PROJECT}` (§2). That combination was built and is green (§1.7). Two richer
   derivations are rejected with reasons in §6.
5. A fifth check lane, `Tests/Checks/run-xcode-checks.sh` over `Tests/Checks/XcodeFixture/`: an
   XcodeGen spec, no committed `.xcodeproj`, a macOS framework target, no simulator. Measured 10s
   cold and 3s warm with packages resolved (§4).
6. 001 §11.2 thread 1 is answered: `SourcePackages/` is reachable from the plugin, and
   `checkouts/<package>/templates` exists for a URL-referenced package and does not exist for a
   path-referenced one (§1.6). Exporting `SOURCERY_TEMPLATES` from it stays unbuilt (§6.3).

---

## 1. Current state (measured 2026-09-10)

### 1.1 The fixture and the probe

The project is generated from a 32-line `xcodegen.yml`: a macOS framework target `Probe` whose
sources are one directory holding `Protocols.swift` and `.Sourcery.Mocks.yml`, a dependency on the
`KitCore` product of a local package, and the plugin attached with

```yaml
    buildToolPlugins:
    - plugin: SourcerySwiftCodegenPlugin
      package: SwiftSourceryTemplates
```

The local package carries `KitCore` (declaring `Caching`) and `KitLeaf` (declaring `Reporting`), with
`KitCore` depending on `KitLeaf`. `Protocols.swift` declares `// sourcery: CreateMock protocol
ProfilePersisting: Caching` — 001 §6.1's shape, one hop and two hops away, moved into an Xcode
project.

The probe is a second build-tool plugin, attached to the same target, that emits everything the
`XcodeProjectPlugin` API exposes through `Diagnostics.warning`. Two API facts had to be worked
around to write it, and both are worth recording for anyone writing the next one: `FileList` does not
conform to `Collection` (`target.inputFiles.count` does not compile; `Array(target.inputFiles)`
does), and a type conforming only to `XcodeBuildToolPlugin` is rejected at run time with

> Plugin is declared with the `buildTool` capability, but doesn't conform to the `BuildToolPlugin` protocol

so the probe also had to conform to `BuildToolPlugin` with a body returning `[]`.

### 1.2 The Xcode path runs end to end

Against the fixture above the plugin logged:

```
 - looking for Sourcery configs in: [<project>/App]
 - found configs: [".Sourcery.Mocks.yml"]
```

then synthesized the config with `output:` appended, ran Sourcery (`Processing time 6.12 seconds`,
of which 5.6s was the first-run SwiftTemplate compile), and Xcode compiled the generated
`Mocks.generated.swift` into `Probe`. The dotfile config reaches the plugin because XcodeGen files it
into the Resources build phase; the probe shows it as `type=resource`. A consumer who does not want
the file copied into the product bundle sets its build phase to `none` in their own spec.

### 1.3 `XcodeTarget.dependencies` is empty, for both dependency kinds

The probe printed `PROBE dependencies=0` for a target whose `project.pbxproj` declares both:

```
		dependencies = (
			B494C5F28B579301DA24257B /* PBXTargetDependency */,   /* → target Core */
			…
		);
		packageProductDependencies = (
			AD32DA488DD906E820679EE0 /* KitCore */,
		);
```

Consequences, all three measured:

- The `.product` case of `XcodeTargetDependency.dependencyInfoArray` (`:1039-1045`) is unreachable
  for a package product dependency of an Xcode target, so `derivedSourceRoots` (`:1077-1085`) adds
  nothing from it. The plugin logged `Target "Probe": ${SOURCERY_SOURCES} resolves to 1 source
  directory.`
- The `.target` case (`:1035-1037`) returns `[]` already, and is unreachable as well.
- The generated mock therefore missed both inherited requirements, and the build failed with 001
  §1.1's original symptom:

  ```
  error: type 'ProfilePersistingMock' does not conform to protocol 'Caching'
  error: type 'ProfilePersistingMock' does not conform to protocol 'Reporting'
  ```

001 §3.4 and [README.md:461-462](../../README.md) both describe the expansion as the target's input
directories "plus the module directories of its product dependencies". The second half does not
happen. §2 and §5 correct both.

`context.xcodeProject.targets` does work: the probe printed `PROBE projectTargets=Core,Probe`, and
each of those targets exposes `inputFiles`. That is the only route to another target's sources the
API offers, and §6.1 is why this spec does not take it.

**Caveat, stated because it changes what the fix would be if it were false:** this was measured on a
project XcodeGen generated. A project authored in Xcode's UI writes the same two pbxproj
constructs, and was not separately measured.

### 1.4 A sibling target dependency fails the build

Adding one line to the fixture spec — `- target: Core`, a dependency on a second framework target in
the same project — turns the build red. The probe shows why:

```
PROBE   input type=source   path=<project>/App/Protocols.swift
PROBE   input type=resource path=<project>/App/.Sourcery.Mocks.yml
PROBE   input type=unknown  path=<project>/build/Debug/Core.framework
```

The linked framework is an input file of the depending target. `XcodeTarget.sourceryConfigFileLocations`
(`:1055-1071`) maps every input file to the first path component under the project directory, so the
search set becomes `[<project>/App, <project>/build]`. `<project>/build` does not exist — the build
ran with `-derivedDataPath`, so products went to `DD/Build/Products` — and `contentsOfDirectory`
throws:

```
Error Domain=NSCocoaErrorDomain Code=260 "The folder “build” doesn’t exist."
```

`:652` turns that into `Diagnostics.error`, which fails the plugin's apply step and the build, in 3s,
before Sourcery runs. Removing that single dependency line and rebuilding: `BUILD SUCCEEDED`. No
Xcode project with more than one target and a dependency between them can use the plugin today.

### 1.5 `GIT_ROOT` is the empty string outside a git repository

The scratch fixture is not in a git repository, and the plugin logged

```
Error running git command: 128: fatal: not a git repository (or any of the parent directories): .git
```

then exported `"GIT_ROOT": ""`. A config naming `${GIT_ROOT}/templates/Mocks.swifttemplate` expands
to `/templates/Mocks.swifttemplate` and fails on a path that names nothing. This is not specific to
the Xcode path — the SPM path shares `gitRootDirectory` — and it does not arise for a consumer whose
project is in a repository, which is why §7 puts it last and §9 leaves the question of whether it
should be an error open.

### 1.6 What the Xcode context can reach — 001 §11.2 thread 1

Sourcery resolves to

```
<DerivedData>/SourcePackages/artifacts/swift-sourcery-templates/sourcery/sourcery-2.3.0.artifactbundle/sourcery/bin/sourcery
```

and the probe found `SourcePackages/` by walking up from `context.pluginWorkDirectory` to the
DerivedData root — six components, from
`DD/Build/Intermediates.noindex/BuildToolPluginIntermediates/<project>.output/<target>/<plugin>`. It holds `artifacts`, `checkouts`, `repositories` and
`workspace-state.json`. In the fixture, `checkouts` held `swift-argument-parser` only: this package is
referenced by path, and a path-referenced package has no checkout and no entry in
`workspace-state.json`'s dependency list. A consumer referencing the package by URL — the shape the
README documents — gets `checkouts/swift-sourcery-templates/templates`.

So `SOURCERY_TEMPLATES` **is** derivable in Xcode for URL-referenced consumers, from a DerivedData
layout that no API documents. §6.3 records why this spec does not build it.

### 1.7 XcodeGen generates the plugin attachment, and the hand-listed closure is green

`xcodegen generate --spec xcodegen.yml` writes the plugin into the target as

```
		productRef = 2257BF05C20F8FA687CEFEA9 /* SourcerySwiftCodegenPlugin */;
		productName = "plugin:SourcerySwiftCodegenPlugin";
```

which is what Xcode reads. With the closure hand-listed —

```yaml
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_PROJECT}/Libraries/Kit/Sources
```

— the generated mock carried `cacheLimit` and `report`, and the build passed. That is the rule §2
adopts, measured rather than argued.

---

## 2. The rule after this spec

In an Xcode project, `${SOURCERY_SOURCES}` expands to the target's own input-file directories. It
does not reach a package product, a sibling target, or anything transitive, because the plugin API
reports no dependency edges (§1.3). An author who needs another directory scanned lists it in
`sources:` beside the placeholder, as an absolute path built from `${SOURCERY_PROJECT}`.

`SOURCERY_TEMPLATES` is still not exported and a bare template name still does not resolve, unchanged
from 001 §4.5. Templates are named by path in an Xcode project.

Everything else the plugin does — config discovery, the synthesized copy, the supplied `output:`, the
`output:` check, the passthrough, the collision diagnostic — behaves as it does under SPM, and §4
gates that claim rather than repeating it.

---

## 3. The fix: a config location that is not there is not an error

`:647-655` treats every failure of `contentsOfDirectory` as `Diagnostics.error`. A location that does
not exist is a normal consequence of §1.4's derivation and must not fail the build: skip it and
continue. A location that exists and cannot be read stays an error — that is a real problem with a
real cause, and silencing it would hide it.

The alternative fix, filtering `inputFiles` by type before deriving locations, is rejected: the
config arrives as `type=resource` (§1.2) and a filter narrow enough to drop
`build/Debug/Core.framework` would have to keep resources, so it would turn on the `.unknown` type
rather than on whether the directory is there. The failing condition is the missing directory, so
that is what the fix tests.

Recorded as decision F1.

---

## 4. The lane

### 4.1 Where it lives and what it is

`Tests/Checks/XcodeFixture/`, with `Tests/Checks/run-xcode-checks.sh` beside the three existing
scripts. It is a red/green gate over the plugin's Xcode path, which is the plugin lane's job for the
SPM path, so it belongs beside it rather than under `Tests/Examples/`.

Committed: `xcodegen.yml`, the target sources, the configs, the local package. Not committed: the
`.xcodeproj`, which the lane generates. [`.gitignore`](../../.gitignore) does **not** cover it today —
it has no `*.xcodeproj` entry — so step 1 adds one. The lane runs
`xcodegen generate --spec xcodegen.yml -q` and then `xcodebuild`, the pattern
`modaal-agent-duet-tutorials/scripts/run-tree.sh:143-146` uses.

The target is a **macOS framework**: no simulator, no signing, no `Info.plist`. The plugin path under
test does not vary by platform, and this keeps the lane's requirements equal to the plugin lane's.

### 4.2 Gates

| gate | what it proves |
| --- | --- |
| **runs** | the plugin's Xcode path discovers a `.Sourcery.*.yml` that reaches it as a Resources-phase file, synthesizes a config into `BuildToolPluginIntermediates/…/.sourceryConfigs/`, and Xcode compiles the generated file into the target |
| **closure** | the synthesized config's `sources:` block holds exactly the target's own input directories — the §2 rule, asserted rather than assumed, so a future API change that starts reporting dependencies shows up here |
| **hand-listed** | a `${SOURCERY_PROJECT}`-rooted entry beside the placeholder is expanded and scanned, and the mock for the refining protocol carries the inherited requirements (§1.7) |
| **sibling target** | a target depending on a second target in the same project builds — the red control for §3, and the case that fails today |
| **defaults** | a config carrying only `templates:` gets `sources:` and `output:` supplied, as under SPM |
| **determinism** | a second `xcodebuild` with no source change leaves the synthesized config byte-identical |
| **bare name** | a bare template name fails with the diagnostic at `:516`, naming the reason — the documented Xcode degradation, kept honest |

### 4.3 Cost

Measured on the scratch fixture: **10s** for a build with `DD/Build` removed and packages already
resolved, **3s** warm. First resolution downloads the pinned Sourcery artifact bundle, which the
plugin lane's cache already covers for CI. `xcodegen` becomes a contributor and CI dependency
(`brew install xcodegen`), which is the cost 001 §11.2 asked to weigh; the alternative it weighed it
against was a committed `.xcodeproj`; F3 records the line counts that decide it.

### 4.4 CI

A fifth lane in [`ci.yml`](../../.github/workflows/ci.yml) beside `checks`, `cli` and `plugin`, on
`macos-15`, gated by the same change filter. It needs no simulator, so it does not belong with the
`example-project` lane.

---

## 5. Docs

[README.md:456-466](../../README.md), "Xcode projects", currently states the product-module half of
the expansion that §1.3 measured false. It becomes: the expansion is the target's own input-file
directories; name any other directory explicitly with `${SOURCERY_PROJECT}`, with the fixture's
config as the example. The `SOURCERY_TEMPLATES` line at README:441 and the bare-name paragraph stay
as they are — they were already accurate.

CONTRIBUTING gains a row in its lane table at CONTRIBUTING.md:268-272, in that table's `| lane |
command | needs |` shape — `| xcode | ``Tests/Checks/run-xcode-checks.sh`` | Xcode and ``xcodegen``;
~10s cold, 3s warm |` — and `xcodegen` in its dependency table.

A CHANGELOG entry records the §3 fix as the consumer-visible change: an Xcode project with two
targets and a dependency between them could not build, and now can.

---

## 6. Rejected, and what stays deferred

### 6.1 Every target in the project

`context.xcodeProject.targets` works (§1.3), so `${SOURCERY_SOURCES}` could expand to every target's
input directories. Rejected: the API reports no dependency edges, so there is no way to narrow the
set to what the target actually depends on. Every consumer would scan every target in the project,
including test targets and unrelated apps, and would have no way to opt out short of abandoning the
placeholder. The hand-listed form of §2 costs one line per directory and says what it means.

### 6.2 The resolved package checkouts

`SourcePackages/checkouts/*` plus the path-referenced packages in `workspace-state.json` would reach
`KitCore` and `KitLeaf` in the fixture. Rejected for this spec on the same narrowing problem as §6.1,
compounded by resting on an undocumented DerivedData layout for the source set rather than for a
single tool path.

### 6.3 `SOURCERY_TEMPLATES` in Xcode

Feasible (§1.6) and not built here. It would work for a URL-referenced consumer, silently not work
for a path-referenced one, and depends on a DerivedData layout no API documents. The lane in §4 is
what makes building it later a measurable change rather than a guess: the **bare name** gate records
today's behaviour, so the commit that adds derivation has something to turn from red to green. Left
open in §9.

---

## 7. Phasing

Each step is a commit that stands on its own and leaves `master` green.

1. **The lane, red on §1.4.** `Tests/Checks/XcodeFixture/`, `run-xcode-checks.sh`, the CI lane, and
   every gate in §4.2 except **sibling target**, which is written and expected to fail. Landing the
   fixture first is what makes step 2 a measured before/after rather than an assertion.
2. **The §3 fix.** `:647-655` skips a location that does not exist. The **sibling target** gate turns
   green in the same commit.
3. **Docs.** README §"Xcode projects" corrected per §5, CONTRIBUTING's two tables, the CHANGELOG
   entry.

Step 1 is worth landing alone: it is the first coverage `XcodeBuildToolPlugin` has ever had, and 001
§11.2 named the absence of it as the reason the Xcode path could not be worked on.

---

## 8. Decisions

- **F1 — A missing config location is skipped, an unreadable one is an error.** §3. The failing
  condition measured in §1.4 is a directory that is not there, so that is the condition the fix
  tests; a directory that exists and will not open keeps its `Diagnostics.error`.
- **F2 — The Xcode closure stays the target's own directories, and the author names the rest.** §2,
  and §6.1/§6.2 for what was weighed against it. The API reports no dependency edges, so every richer
  derivation is "scan more than you asked for" with no way to narrow it; one explicit line per
  directory is the smaller cost, and it is measured green in §1.7.
- **F3 — The lane's project is generated, not committed.** §4.1. Measured on the scratch fixture:
  `xcodegen.yml` is 32 lines and reviewable in a diff, `project.pbxproj` for the same two-target
  project is 489 lines of generated identifiers. 001 §11.2 asked whether a committed `.xcodeproj` was
  worth its maintenance; at that ratio, with `xcodegen` a `brew install` away, it is not.
- **F4 — The lane's target is a macOS framework.** §4.1. The code path under test does not vary by
  platform, and a simulator would make this the second lane that needs one.
- **F5 — The lane asserts the degraded closure rather than only the successful build.** §4.2,
  **closure** gate. The expansion being one directory is a fact about an API that may change; a gate
  that reads the synthesized config reports that change instead of silently getting better.

---

## 9. Open questions

1. **Should an empty `GIT_ROOT` be an error?** §1.5. The plugin exports `""` after a failed
   `git rev-parse`, and a config interpolating it fails on a path that names nothing. An error at
   plan time naming the config and the variable would say so directly. Unmeasured: whether any
   consumer builds outside a repository deliberately.
2. **`SOURCERY_TEMPLATES` in Xcode.** §6.3. Reachable, undocumented, and split between URL- and
   path-referenced consumers. Worth revisiting when a consumer asks for a bare template name in an
   Xcode project, with the §4.2 **bare name** gate as the before-measurement.
3. **Does an Xcode-authored project report dependencies the same way?** §1.3's caveat. Everything
   here was measured against an XcodeGen-generated `project.pbxproj`. If a UI-authored project does
   report edges, F2 is the decision that changes, and the **closure** gate is where it would show.
