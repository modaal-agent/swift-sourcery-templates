# 001 follow-up — The Xcode path: what it derives, the discovery bug, a check lane built with
XcodeGen, and where templates come from

**Status:** Part I (§1–§9) is implemented — see §7 for what landed. Part II (§10–§20) is proposed
and not implemented. Written 2026-09-10.

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

---

# Part II — Where the templates come from

**Status:** Proposed, not implemented. Written 2026-09-10, after Part I's §7 landed as `37d7773`
(the lane), `a662e5a` (the §3 fix) and `fa07498` (the docs).

**Measurements:** every number and quoted path in §11 was produced on 2026-09-10 with Xcode 26.5
(build 17F42) and the SwiftPM in the same toolchain, using throwaway packages and Xcode projects in a
scratch directory outside this repository. Nothing in the repository was changed to take them.

**Scope:** `Package.swift`, `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`,
`Scripts/assemble-release.sh`, `.github/workflows/release.yml`, `Tests/Checks/`, `Tests/Examples/`,
`README.md`, `CONTRIBUTING.md`. No template change.

**Obsoletes:** §6.3 and §9 question 2. Both framed `SOURCERY_TEMPLATES` in Xcode as reachable only
through the DerivedData layout, split between URL- and path-referenced consumers. §11.1 and §11.2
measure a route that does not read that layout at all and does not care how the package was
referenced.

---

## 10. What this part is for

A bare template name does not resolve in an Xcode project.
`XcodeProjectPlugin.XcodePluginContext.shippedTemplatesDirectory` returns `nil`
(`SourcerySwiftCodegenPlugin.swift:1024`) because there is no package graph to walk, so
`resolveTemplate` falls through to the warning at `:516` and Sourcery then fails on a path that names
nothing. `Tests/Checks/XcodeFixtureRed/BareName` is that failure, held as a red control since
`37d7773`.

The fix is two routes to a `templates/` directory that need no package graph, tried in the order §12
sets: the plugin's own source location, and the artifact bundle that ships the engine. The second
means pinning this repository's bundle rather than Sourcery's upstream one, which
`Package.swift:17-21` pins today. §11.5 measures what each carries and §14 is the accounting; the
download changes by 57 KB, so size decides nothing here.

---

## 11. Measured

### 11.1 A binary target's bundle is extracted whole, and the executable's siblings survive

Upstream Sourcery's own bundle proves this without any change here. Extracted by an Xcode build into
`<DD>/SourcePackages/artifacts/swift-sourcery-templates/sourcery/sourcery-2.3.0.artifactbundle/`, it
holds, beside `sourcery/bin/sourcery`:

| path in the bundle | size |
| --- | --- |
| `sourcery/bin/sourcery` | 56 MB |
| `sourcery/Sourcery.docset` | 2.0 MB |
| `sourcery/Resources` | 668 KB |
| `sourcery/Templates` | 72 KB |
| `sourcery/CHANGELOG.md` | 52 KB |
| `sourcery/bin/ejs.js` | 44 KB |
| `sourcery/README.md` | 16 KB |
| `sourcery/LICENSE`, `info.json`, empty `bin/` | 5 KB |
| **total** | **59 MB** |

SwiftPM unzips the bundle and prunes nothing: an artifact bundle can carry arbitrary files, and they
are on disk at a fixed offset from the executable when the plugin runs.

### 11.2 One bundle can declare several executables, and each resolves by artifact name

A throwaway bundle declaring two artifacts (`engine` → `engine/bin/engine`, `helper` →
`helper/bin/helper`) with a `templates/` directory at its root, in a package a consumer referenced by
URL. `context.tool(named:)` resolved both, on both plugin APIs:

```
SPM     tool(engine)=<scratch>/checkouts/bundleprobe/Fake.artifactbundle/engine/bin/engine
        upThree=<scratch>/checkouts/bundleprobe/Fake.artifactbundle
        templatesExists=true contents=["Marker.swifttemplate"]
Xcode   tool(helper)=<DD>/SourcePackages/checkouts/bundleprobe/Fake.artifactbundle/helper/bin/helper
        upThree=<DD>/SourcePackages/checkouts/bundleprobe/Fake.artifactbundle
        templatesExists=true contents=["Marker.swifttemplate"]
```

The artifact name must equal the binary target's name, so a package pins one artifact per
`.binaryTarget`, but one published zip can serve several of them.

The probe's bundle was declared with `path:`, so it sat in the checkout beside `Package.swift`;
§11.1's upstream bundle is the `url:` shape and lands under
`artifacts/<package>/<target>/<bundle>.artifactbundle/`. The two together cover both forms, and in
both the bundle root is the directory holding `info.json` — which is what §13 keys on rather than
on either path shape. A `url:` binary target declaring two artifacts was not separately measured.

This is the whole mechanism. It reads no package graph, so it behaves identically under
`PackagePlugin` and `XcodeProjectPlugin`; it reads no DerivedData layout, so §6.3's URL-versus-path
split does not arise; and the layout it depends on is written by
`Scripts/assemble-release.sh:88-96` in this repository and pinned by checksum in `Package.swift`.

### 11.3 `#filePath` also works, and is rejected

`#filePath` in the plugin's source expands at plugin-compile time to the absolute path of that file in
the consumer's checkout, from which `templates/` is a fixed offset. Measured in all four consumer
shapes:

| consumer | `#filePath` at run time | `<up 3>/templates` |
| --- | --- | --- |
| SPM, package by path | `<pkg>/Plugins/PathProbe/PathProbe.swift` | found |
| SPM, package by URL | `<scratch>/checkouts/tmplprobe/Plugins/…` | found |
| Xcode, package by path | `<pkg>/Plugins/…` | found |
| Xcode, package by URL | `<DD>/SourcePackages/checkouts/tmplprobe/Plugins/…` | found |

No path remapping is applied to plugin compilation, and the baked path does not go stale: rebuilding
with the checkout relocated (`-clonedSourcePackagesDirPath` moved, same DerivedData, so the cached
plugin executable was a candidate for reuse) recompiled the plugin — the compilation-input hash went
from `1843100…` to `0fca2c0…` — and the path tracked the move.

Its correctness rests on two behaviours nothing documents: that the source path is part of SwiftPM's
plugin-compilation input hash, and that no future toolchain remaps paths when compiling a plugin. If
either changes, the plugin reads templates from a path that is not there, or from a stale checkout.
That is why it is not used alone. It is used *first*, ahead of §11.2's bundle, and the bundle is what
catches it when it fails — a directory that is not there is a condition the plugin tests, so the
failure falls through rather than propagating. §12 is the order and F6 is the decision.

### 11.4 `DEBUG` is not defined when a plugin is compiled

Both plugin APIs, measured with `#if DEBUG` in the probe:

```
SPM     PROBE   DEBUG=not-defined
Xcode   PROBE   DEBUG=not-defined
```

A `#if DEBUG` fallback would therefore be compiled out everywhere, this repository's own check lanes
included — the lanes it was meant to serve. §16 keeps them honest without a compile-time gate.

### 11.5 What an adopter downloads today

Of the 59 MB in §11.1's table, the plugin runs `sourcery/bin/sourcery` and reads nothing else. The
docset, `Resources`, upstream's `Templates`, `ejs.js`, the README and the CHANGELOG are about 2.8 MB
that no build here touches. `Scripts/assemble-release.sh:25-28` already records that `ejs.js` is not
vendored into this repository's own bundle and why.

This repository's `templates/` is 124 KB. A release build of `mock-templates` is 1,774,976 bytes for
one architecture; the shipped binary is universal, so roughly twice that.

Those are extracted sizes. What a resolution actually downloads is the zip, and §14 compares those:
22,613,709 bytes for Sourcery's, 22,672,041 for this repository's 0.7.0.

### 11.6 Who consumes the published assets today

Surveyed 2026-09-10 across `~/Projects/modaal-*` and `~/Modaal-Projects`, because §14 first proposed
dropping an asset and the repositories on this machine say who reads it.

`modaal-agent-duet-tools/Sources/duet/Mocks.swift:229-274` provisions both assets, and which one it
takes depends on the verb:

- `duet mocks` (regenerate) fetches `swift-sourcery-templates-<tag>.artifactbundle.zip` and takes
  **all three pieces out of it** — `mock-templates/bin/mock-templates`, `sourcery/bin/sourcery` and
  `templates/` — at fixed offsets from the bundle root, which is the same layout contract §13
  proposes for the plugin. `duet-tools/contracts/manifest.md:114-118` documents the manifest's
  `mocks.bundle:` pin as "the bundle carries engine, templates and the `mock-templates` CLI together,
  so this one pin replaces an engine/templates version pair".
- `duet mocks --check` (validate) fetches `mock-templates-<tag>-macos.zip` when no full bundle is
  already cached — `validate` reads the fingerprint block and the sources and runs neither the engine
  nor a template, so kilobytes are all it needs. That path runs in CI:
  `modaal-wikimemory-dgra0/.github/workflows/parity.yml:68` and
  `modaal-onesec-py38p/.github/workflows/parity.yml:318`, plus
  `modaal-wikimemory-dgra0/scripts/run_tests.sh:164`.

Both consumers pin `bundle: 0.6.2` in `parity/manifest.yaml`, as do nine tutorial trees under
`modaal-agent-duet-tutorials`.

`modaal-firebase-wrappers/scripts/generate-mocks.sh` uses neither asset: it clones the templates repo
by tag and calls a Homebrew `sourcery` directly, never `mock-templates`. `modaal-foundation-core` and
`modaal-foundation-spritekit` reference this repository nowhere at all.

So both published assets are live, and the artifact bundle's internal layout is already a contract a
downstream tool depends on.

---

## 12. The rule after this part

A template named without a path resolves in an Xcode project exactly as it does in a package, and
`SOURCERY_TEMPLATES` is exported on both. `shippedTemplatesDirectory` is the first of these that is a
directory on disk:

| | route | available on | version it yields |
| --- | --- | --- | --- |
| 1 | the package graph — the walk at `SourcerySwiftCodegenPlugin.swift:902-915` | SwiftPM only | the consumer's checkout |
| 2 | `#filePath`, up three components from the plugin source | both APIs | the consumer's checkout |
| 3 | the pinned artifact bundle, §13's walk | both APIs | the bundle `Package.swift` names |

Under the release scheme in §15 all three name templates of the same version for a consumer at a tag,
because the bundle a tag pins was built from that tag's own `templates/`. The order is what makes the
routes independent rather than what picks between versions: route 1 uses a documented API and needs a
graph, route 2 needs neither but rests on the undocumented behaviours in §11.3, route 3 needs neither
a graph nor a compiler behaviour but is only as current as the pin. Each covers the others' failure,
and no route is load-bearing alone.

Where the order matters is inside this repository: on a branch, `Package.swift` still pins the last
published bundle, so route 3 is a release behind while routes 1 and 2 are the working tree. §16 is
what that buys.

The plugin logs which route supplied the directory, beside the remarks it already emits for every
resolved template. Without that a consumer cannot tell from a build which `templates/` they got.

Where no route yields a directory, the behaviour is today's: the warning at `:516`, then Sourcery
fails on the name.

---

## 13. The two mechanisms

**Route 2, `#filePath`.** Three components up from the plugin's own source file is the package root —
`Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift` — and `templates` under it.
Measured in all four consumer shapes in §11.3.

**Route 3, the bundle.** Given the tool path, walk up until a directory containing `info.json` is
found — that is the artifact bundle root — then take `templates` under it if it is a directory.

Both check that the directory exists before returning it, which is what lets §12's order work: a
route that cannot answer returns nothing and the next one is tried, rather than returning a path that
is wrong.

Not "three components up". That number is true of the layout
`Scripts/assemble-release.sh:88-96` writes today (`sourcery/bin/sourcery`), and it would be silently
wrong the day a variant path in `info.json` gains or loses a component. Searching for the file that
defines a bundle root is the same cost and says what it means. Recorded as decision F7.

The plugin already walks a tool path this way: `locateSourceryExecutable` (`:99-112`) probes
`<tool>/bin/sourcery` for the case where the bundle is zipped one level too deep.

---

## 14. What the bundle carries, and what this costs

The published assets do not change. `Scripts/assemble-release.sh` keeps building one artifact bundle
holding the engine, `templates/` and the `mock-templates` CLI, and keeps publishing the CLI's own
`mock-templates-<version>-macos.zip` beside it. §11.6 is why: `duet mocks` reads all three pieces out
of the bundle, `duet mocks --check` reads the standalone CLI zip in two CI lanes, and a downstream
contract documents the bundle as carrying all three. Removing either asset breaks a shipping
pipeline in exchange for a smaller download, so neither is removed. Recorded as decision F11.

The accounting is on the zips, which is what a resolution downloads — §11.1's table is what the
extracted bundle occupies on disk, and the two differ by more than half:

| asset an adopter downloads | bytes |
| --- | --- |
| `sourcery-2.3.0.artifactbundle.zip`, pinned today | 22,613,709 |
| `swift-sourcery-templates-0.7.0.artifactbundle.zip`, pinned after | 22,672,041 |
| **difference** | **+58,332** |

57 KB more per resolution, cached by SwiftPM and paid once per version. The 2.8 MB of upstream
material the plugin never reads and this repository's `templates/` plus universal CLI compress to
within a rounding error of each other, so the size question does not decide anything here in either
direction.

One thing an adopter loses: the resolved bundle no longer carries upstream's `bin/ejs.js`, so a
consumer driving the plugin with a `.ejs` template of their own loses the runtime that serves it.
`Scripts/assemble-release.sh:25-28` records why this repository's bundle omits it and the smoke test
that keeps our own templates free of it. §20 question 2 is whether anyone is affected.

What improves is that the bundle a consumer resolves for the plugin is the same artifact `duet`
already resolves for `duet mocks`, pinned by the same tag — one download and one version for both,
where today a repo using both pins Sourcery's bundle through the plugin and this repository's bundle
through the manifest.

---

## 15. Releasing without skew

A `binaryTarget` pins a URL and a checksum, so the zip must exist before the commit that references
it. Cutting `X.Y.Z` from a commit whose `Package.swift` points at the previous release ships a plugin
whose templates are one release old, and nothing in the build says so. That is worse than the
degradation Part I documented, because a consumer cannot see it.

The scheme, in order:

1. Tag `templates-X.Y.Z` at commit `C`. A release lane builds the artifact bundle from `C`'s
   `templates/` and publishes it, with its SHA-256.
2. Commit `C'`, which changes `Package.swift` and nothing else: the binary target's `url` and
   `checksum` become that asset's.
3. Tag `X.Y.Z` at `C'`. `C'`'s `templates/` is `C`'s `templates/`, so the bundle a consumer resolves
   at `X.Y.Z` carries exactly the templates in the commit `X.Y.Z` names.

Two changes this needs:

`.github/workflows/release.yml:9-11` triggers on `tags: ['*.*.*']`, and `templates-0.8.0` matches
that glob — `templates-0` `.` `8` `.` `0`. Left alone, step 1 would publish a full release. The
trigger has to distinguish the two tag shapes and route each to its own job.

And step 3 needs a gate, because the invariant it rests on — that `C'` changed only `Package.swift` —
rests on a person having done so. In `release.yml`, on an `X.Y.Z` tag, before anything is published:
download the bundle `Package.swift` pins and refuse to publish unless its `templates/` is
byte-identical to the commit's `templates/`. The comparison is mechanical and it catches every way
the promise can break, including a template edited between the two tags. Recorded as decision F8.

**The bundle a tag pins may be older than the tag, and that is fine.** A release that changes only
the plugin, the CLI or the docs needs no new `templates-X.Y.Z`: step 2 is skipped, `Package.swift`
keeps the pin it has, and F8's comparison passes because `templates/` did not move. What the scheme
guarantees is not that the two tags advance together but that the pinned bundle's `templates/` is the
tag's `templates/`.

**The order also means `master` can never name an asset that does not exist.** The pin lands in a
commit *after* the asset is published, so a `templates-X.Y.Z` whose lane fails publishes nothing and
gets no pin bump — `Package.swift` keeps pointing at the last asset that did publish, and resolution
keeps working. There is no state in which the repository references a zip that was never uploaded.

**Bootstrapping needs no new tag.** `swift-sourcery-templates-0.7.0.artifactbundle.zip` is already
published, 22,672,041 bytes, and carries `templates/` — `duet` reads it from the 0.6.2 bundle the
same way (§11.6). The first pin can name it, and the two-tag order starts at the next release.

---

## 16. What the order buys this repository's own lanes

On a branch, `Package.swift` pins the last published bundle, so route 3 is a release behind. Routes 1
and 2 are the working tree, and both come first, so both lanes keep gating the templates being
edited.

**The plugin lane** is covered by route 1 alone. `Tests/Checks/PluginFixture` reaches this repository
by path, so the graph walk at `SourcerySwiftCodegenPlugin.swift:902-915` finds the working tree, as
it does today. Nothing about that lane changes.

**The Xcode lane** has no graph, and route 2 is why it is still honest: `#filePath` resolves to the
plugin source in this checkout, so `Tests/Checks/XcodeFixture` generates from the working tree's
templates. That is what makes the bare-name gate a real gate rather than an assertion about a
published artifact — it can assert generated content, the same way the plugin lane does.

`Tests/Checks/XcodeFixtureRed/BareName` therefore moves out of the red project and into
`XcodeFixture` as a green gate: a bare `- Mocks` resolves, the log names route 2 as what supplied the
directory, and the generated mock carries the requirements the fixture declares. §6.3 said the red
control existed so that a later commit adding derivation would have a gate to turn from red to green;
steps 4 and 5 of §18 are that change.

Route 3 is then exercised by nothing in CI, which §17 is the answer to.

---

## 17. The example that documents the consumer's shape

Every fixture here reaches this repository by path, because that is what a fixture in this repository
can do. Two things therefore go unchecked by any lane: the package resolved from a published URL at a
tag, which is what an adopter writes, and route 3 as the source of `templates/` — §16 is exactly the
argument that routes 1 and 2 win on every branch, so nothing in CI ever falls through to the bundle.

`Tests/Examples/ExampleProjectXcode/` is that shape — an XcodeGen spec referencing
`https://github.com/modaal-agent/swift-sourcery-templates` at a released version, with a config
naming a template by bare name. It is documentation, not a gate: it necessarily lags one release, and
wiring it into `ci.yml` would make every branch depend on the last published artifact, which §16 is
written to avoid.

Something has to say when to look at it, or it stops building and nobody finds out. It goes in
CONTRIBUTING's release procedure as a step: after a release publishes, regenerate and build it, and
record that it built. Recorded as decision F9; §20 question 3 is whether that is enough.

---

## 18. Phasing

Each step is a commit that stands on its own and leaves `master` green.

1. **Give the upstream engine pin a home of its own.** `Scripts/assemble-release.sh:46-48` finds the
   engine to vendor by taking the *first* `artifactbundle.zip` URL in `Package.swift` and parsing the
   version out of its path. The moment `Package.swift` names a second bundle, that picks by position
   — it would vendor this repository's own previous release as "the engine", with a version parsed
   from the wrong URL, and the smoke test would still pass. `Tests/Checks/ensure-sourcery.sh:8-9`
   duplicates the same version under "Keep in step with Package.swift's binary target", which stops
   being followable for the same reason. Both read an unambiguous pin instead. No behaviour change,
   and it has to land before step 3. Recorded as decision F12.
2. **Teach the release lane the two tag shapes.** `release.yml` routes `templates-X.Y.Z` to an
   assemble-and-publish job and `X.Y.Z` to the existing one, and the `X.Y.Z` job gains F8's
   templates-match gate. `Scripts/assemble-release.sh` is otherwise unchanged — it already builds the
   bundle §14 keeps.
3. **Pin this repository's bundle.** `Package.swift`'s `sourcery` binary target moves from Sourcery's
   zip to `swift-sourcery-templates-0.7.0.artifactbundle.zip`, which is already published (§15). The
   artifact name in that bundle's `info.json` is `sourcery`, so the target keeps its name and
   `context.tool(named: "sourcery")` is untouched. Nothing resolves templates from it yet; the gate
   is that all five lanes still build and the engine still reports 2.3.0.
4. **Resolve the templates.** §12's order and §13's two mechanisms:
   `shippedTemplatesDirectory` in the Xcode extension stops returning `nil`, the SwiftPM
   implementation gains routes 2 and 3 behind its graph walk, and the plugin logs which route
   supplied the directory. `SOURCERY_TEMPLATES` is exported on both paths.
5. **Move the bare-name gate.** §16: out of `XcodeFixtureRed/` and into `XcodeFixture/` as a green
   gate that asserts resolution, the route named in the log, and the generated content.
   `XcodeFixtureRed/` keeps its shape for the next red control.
6. **The example.** §17, plus its step in CONTRIBUTING's release procedure.
7. **Docs.** README §"Xcode projects" loses the second degradation and the exported-variables note
   loses `SOURCERY_TEMPLATES`; README's artifact-bundle section says the bundle is what the plugin
   itself resolves; CONTRIBUTING's release procedure gains the two-tag order; a CHANGELOG entry
   records that a bare template name now works in an Xcode project, that the engine an adopter
   downloads is this repository's bundle rather than Sourcery's, and that `bin/ejs.js` is not in it.

Steps 1 and 2 carry no consumer-visible change and could land in either order. Step 3 is where
`master` starts depending on an asset this repository published, and §15 is why that cannot leave the
repository unresolvable.

---

## 19. Decisions

- **F6 — Both mechanisms, checkout before bundle.** §12, §13. `#filePath` and the bundle both work
  in all four consumer shapes (§11.2, §11.3) and each fails where the other does not: `#filePath`
  rests on two undocumented behaviours — the source path being part of the plugin's
  compilation-input hash, and no toolchain remapping paths during plugin compilation — while the
  bundle rests on a layout this repository writes and pins by checksum but is only as current as the
  pin. Every route tests that the directory exists before returning it, so a route that cannot answer
  falls through instead of returning a wrong path. Neither is load-bearing alone, and the plugin logs
  which one answered.
- **F12 — The upstream engine pin is read by name, not by position.** §18 step 1.
  `Scripts/assemble-release.sh:46-48` currently takes the first `artifactbundle.zip` URL in
  `Package.swift`; once a second one is there, that silently vendors the wrong zip and parses a
  version out of the wrong path. This has to land before the pin moves.
- **F7 — Find the bundle root by looking for `info.json`, not by counting components.** §13. The
  count is true of today's layout and would be wrong, with no diagnostic, if a variant path in
  `info.json` changed shape. Both conditions are checked at run time; failing them produces the
  existing warning.
- **F8 — A release refuses to publish if the pinned bundle's templates differ from the commit's.**
  §15. The two-tag scheme's correctness rests on a human having changed only `Package.swift` between
  the tags. The gate is a byte comparison and it catches every way that promise can break.
- **F9 — The by-tag example is documentation with a named maintenance step, not a lane.** §17. Making
  it a lane would make every branch depend on the last published artifact, which is the coupling §16
  exists to avoid; leaving it with no owner means it rots.
- **F11 — No published asset is removed or repackaged.** §14, measured in §11.6. The bundle keeps
  the CLI and the standalone CLI zip stays. Dropping either to save about 3.5 MB per resolution would
  break `duet mocks` and `duet mocks --check` respectively, the second of which is a CI gate in two
  repositories. The change costs adopters about 600 KB and buys §12's rule.
- **F10 — `#if DEBUG` is not available as a gate anywhere in this plugin.** §11.4, measured on both
  APIs: the symbol is undefined when SwiftPM and Xcode compile a plugin, so a `#if DEBUG` branch is
  compiled out of every build, including this repository's own lanes.

---

## 20. Open questions

1. **Should `duet`'s bundle pin and the plugin's become one pin?** §11.6, §14. After this, a repo
   using both resolves the same zip twice under two version numbers: `mocks.bundle:` in
   `parity/manifest.yaml` and whatever tag its `Package.swift` names for this package. They can
   disagree. Unmeasured: whether `duet` could read the plugin's pin, or whether the two are
   deliberately independent.
2. **Does anything still consume upstream Sourcery's `bin/ejs.js` through this package?** §14. After
   the pin moves, the resolved bundle no longer carries it, so a consumer driving the plugin with
   their own `.ejs` template loses the runtime that serves it. `Scripts/assemble-release.sh:25-28`
   records that this repository's own templates are all `.swifttemplate` and that a smoke test keeps
   them that way; nobody has checked whether a consumer's are.
3. **Is a release-procedure step enough to keep §17's example alive?** F9. The alternative is a
   scheduled lane that builds it against the latest tag — which is a gate on a published artifact,
   but on a schedule rather than on every branch, so it fails the release rather than the branch.
