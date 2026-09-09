# 001 — A self-sufficient build-tool plugin: a derived source closure, a synthesized config, and the options the author keeps

**Status:** Draft, 2026-09-09. Nothing implemented. Every measurement in §1.4 and §1.5 was run
against this checkout on 2026-09-09 with Sourcery 2.3.0 and the Xcode 26.5 toolchain.
**Scope:** `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift`,
`Examples/ExampleProjectSpm/`, `Checks/`, README and CONTRIBUTING. No template change. No change to
`mock-templates` — the CLI stays policy-free (§9, D6).
**Baseline:** `master` at `4b1d0bb` ("Retire the CocoaPods distribution").
**Relates to:**
- `2a2857c` on branch `tt` (2024-02-28, message "tt", never merged) — the first attempt at exactly
  this. §1.3 records what it did and §1.4/A the measurement that shows why it could not have worked.
- [CONTRIBUTING.md §Pitfalls](../../CONTRIBUTING.md) — "Sourcery only knows the declarations it
  parses": a protocol refining one from another module generates a mock missing those requirements.
  That pitfall is the user-visible symptom this spec removes for the plugin path.
- [README.md](../../README.md) — the `SOURCERY_TARGET_*` env-var contract this spec extends without
  breaking.

---

## 0. TL;DR

1. The plugin exports **one level** of the package graph as env vars, and the author hand-lists each
   var in `sources:`. A module reachable only transitively has no var and cannot be listed at all
   (§1.1). That is the gap.
2. The information was never missing. `Target.recursiveTargetDependencies` and the recursive
   `Package.dependencies[].package` walk give the plugin the full closure (§1.4/E). **Injection** is
   the wall: with `--config` in play Sourcery discards command-line `--sources`, and a config entry
   cannot fan one env var into many (§1.4/A, measured).
3. So the plugin **synthesizes a config**. It copies the author's `.Sourcery.<Name>.yml` byte for
   byte into `pluginWorkDirectory`, replacing a declared placeholder line — `- ${SOURCERY_SOURCES}` —
   with one `- "<dir>"` line per module directory in the closure, and runs Sourcery against the copy
   (§4). A config that declares no inputs and no output gets both appended, which is free: Sourcery
   rejects a config missing either key today (§1.4/G, §1.4/H), so nothing that works now changes
   meaning.
4. **Directories, not files.** `2a2857c` joined every source file path of the closure into one env
   var; this derivation emits one directory per source module — 30-odd lines instead of thousands,
   and stable across an added file, which keeps Sourcery's cache warm (§3.2, §9 D2).
5. **The author keeps every option with more than one right answer.** `args.import`,
   `excludedSwiftLintRules` and the choice of template are authored intent, and the copy carries them
   through unread. What has a single right answer, the plugin supplies: the output directory, and
   `args.testable` when the test target depends on exactly one first-party module (§5, §4.6).
6. Second self-sufficiency gap, same size: a consumer has **no way to name the shipped templates**.
   The example writes `${GIT_ROOT}/templates/Mocks.swifttemplate`, which only resolves because the
   example lives inside this repo. The plugin finds its own package in the graph, exports
   `SOURCERY_TEMPLATES`, and resolves a **bare template name** — `- Mocks` — to the shipped file, so
   a consumer names a template the way the CLI's fingerprint already records it (§4.5).
7. A target may carry several configs, and a config several templates: Sourcery writes one
   `<Template>.generated.swift` per `templates:` entry (§1.4/F). Mocks beside the test target,
   Component and TypeErase beside the sources — that is the adopter shape, and it is what the naming
   rules have to serve (§4.6).
8. The example package grows a third target whose protocol is reachable only transitively, and the
   mocks config drops its explicit `RIBs` line. Both are red controls: they fail to compile on
   today's plugin and pass after (§6).
9. Backward compatible. Every `SOURCERY_TARGET_*` var keeps its name and value; a config with no
   placeholder is copied unchanged, and a `templates:` entry that names a real file today keeps
   naming it (§9, D5 and D8).

---

## 1. Current state (verified 2026-09-09)

### 1.1 The plugin exports one level

`PluginContext.environmentVars` (`SourcerySwiftCodegenPlugin.swift:199-215`) iterates
`package.targets` — the **root package's** targets only — and, per target, its **direct**
`dependencies`:

| dependency case | exported | what it misses |
| --- | --- | --- |
| `.target(t)` (`:221-222`) | `SOURCERY_TARGET_<owner>_DEP_<t.name>` → `t.directory` | `t`'s own dependencies |
| `.product(p)` (`:224-229`) | `…_DEP_<p.name>_MODULE_<module>` and `…_DEP_<p.name>_TARGET_<target>` per entry of `p.sourceModules` / `p.targets` | the targets those targets depend on, and every package deeper in the graph |

Plus `SOURCERY_TARGET_<t.name>` → the target's own directory, `GIT_ROOT` (`:16-47`, a `git
rev-parse` subprocess), `SOURCERY_PACKAGE` and `SOURCERY_OUTPUT_DIR` (`:109-111`).

The config then names each var by hand. In
`Examples/ExampleProjectSpm/Sources/ExampleProjectSpmTests/.Sourcery.Mocks.yml`:

```yml
sources:
  - ${SOURCERY_TARGET_ExampleProjectSpm}
  - ${SOURCERY_TARGET_ExampleProjectSpm_DEP_RIBs_MODULE_RIBs}
  - ${SOURCERY_TARGET_ExampleProjectSpmTests}/SourceryAnnotations
```

Two consequences, both real today:

- **A transitively-reachable module cannot be listed.** There is no var for it. The author's only
  recourse is a literal path into `.build/checkouts/…` or DerivedData, which is not portable.
- **The Xcode path is worse.** `XcodeTargetDependency.dependencyInfoArray` (`:280-299`) returns `[]`
  for the `.target` case outright, and `XcodePluginContext.environmentVars` (`:262-278`) never
  exports a `SOURCERY_TARGET_<name>` for the target itself.

### 1.2 The CLI does not resolve anything

Worth stating because the recollection that prompted this spec had it the other way round.
`mock-templates` takes a repeatable `--sources` (`Commands.swift:20-21`) and
`SourceSet.enumerate` walks exactly those roots (`SourceSet.swift:14-51`). The doc comment at
`Commands.swift:15-18` is the design:

> The tool is policy-free — it hashes the files it is pointed at and knows nothing about who calls it
> or why; pin policy and source-set derivation live in the calling script.

The transitive index a consumer gets comes from **its own script**: CONTRIBUTING records that the
reference app's `scripts/generate-mocks.sh` derives it from `swift package dump-package`. So the CLI
path is self-sufficient only because a shell script can run arbitrary commands. The plugin cannot;
it has to derive the same set from inside SwiftPM. This spec closes that asymmetry on the plugin
side and changes nothing about the CLI.

### 1.3 What `2a2857c` tried

```swift
let transitiveTargetSourceFiles: String = t.recursiveTargetDependencies
  .flatMap { t in t.sourceModule?.sourceFiles.map { $0.path.string } ?? [] }
  .joined(separator: ", ")
…
("SOURCERY_TARGET_\(t.name)_FILES", "[\(transitiveTargetSourceFiles)]"),
```

with the config collapsed to `- ${SOURCERY_TARGET_ExampleProjectSpm_FILES}` and the hand-listed roots
commented out. The resolution half is right and this spec keeps it. The injection half bet that
Sourcery expands `${}` **before** parsing the YAML, so that a `[a, b, c]` string would re-parse as a
flow sequence. It does not (§1.4/A). The commit is one commit past `cbc6ad0` on branch `tt`, never
merged; its `Package.swift` change to a local path dependency landed on `master` separately.

### 1.4 Measured facts about Sourcery 2.3.0

All nine were run against
`.build/sourcery-2.3.0/sourcery-2.3.0.artifactbundle/sourcery/bin/sourcery`.

**A. `${VAR}` expands after parsing, into one scalar, resolved against the config's directory.**
With `sources: [- ${TEST_FILES}]` and `TEST_FILES="[/…/a/A.swift, /…/b/B.swift]"`:

```
error: '/…/envtest/[/…/a/A.swift, /…/b/B.swift]' does not exist or is not readable.
```

One path, brackets and comma included, prefixed with the config file's own directory. The same
config with a single path in the var generates fine. **This kills the aggregate-env-var route for
good, and it is also the constraint behind §4.3** — a synthesized config in a different directory
changes what every *relative* path in it means.

**B. `--config` discards command-line inputs.** The binary carries the string:

> `Using configuration file at '…'. WARNING: Ignoring the parameters passed in the command line.`

So the plugin cannot pass a derived `--sources` alongside the author's `--config`. Either the config
carries the sources or they are not passed.

**C. Directories are accepted, and overlap is harmless.** A `sources:` list holding a directory, the
same directory again, and a file already inside it parsed each type once
(`// parsed protocols: Alpha Beta`). Dedup is a size and legibility concern, not a correctness one.

**D. `sources:` also takes the `include:` / `exclude:` form,** and `exclude` is honoured (excluding
`b/B.swift` dropped `Beta`). Any placeholder design has to work inside `include:` too.

**E. PackagePlugin exposes the whole graph.** From the Xcode 26.5 plugin API interface:
`Target.recursiveTargetDependencies: [any Target]`, `Target.sourceModule: (any SourceModuleTarget)?`,
`SourceModuleTarget.{moduleName, kind, sourceFiles}`, `ModuleKind.{generic, executable, snippet,
test, macro}`, and `Package.dependencies: [PackageDependency]` where `PackageDependency.package` is a
full `Package` with its own `targets`, `directoryURL` and `dependencies`. Access was never the
blocker.

**F. One output file per template, named after the template.** A config naming two templates with a
directory `output:` wrote `t.generated.swift` and `t2.generated.swift`. So a config is a
(sources, args, output) tuple that can drive several templates, and a generated file's name comes
from its template, never from the config's name. §4.7, D8 and D9 rest on this.

**G. A config without sources is fatal.**

```
error: … 'Invalid sources. 'sources', 'project' or 'package' key are missing.'
```

Note the alternatives: `project:` and `package:` also satisfy the requirement, so "has no sources"
means none of the three keys is present (§4.6).

**H. A config without `output:` is fatal.**

```
error: … 'Invalid output. 'output' key is missing or is not a string or object.'
```

Despite `--output`'s "Default is current path" in `--help`, the config path requires the key. **G and
H together are what make §4.6's defaults strictly additive**: no config that works today omits either
key, so filling them in cannot change the meaning of anything that already runs.

**I. A duplicate top-level key is silent, and the last one wins.** A config with two `output:` keys
generated into the second directory and reported nothing. This is what makes §4.2's step 3 the one
rule that can change a build's meaning if it misreads the document, and it is why that step logs.

### 1.5 The plugin's hard constraints

**It cannot depend on a library.** Measured — a package declaring
`.plugin(name: "P", capability: .buildTool, dependencies: ["Lib"])` fails to build:

```
error: plugin 'P' cannot depend on 'Lib' of type 'library'; this dependency is unsupported
```

So: no Yams, no shared code with `Sources/mock-templates`, no unit-test target that imports the
plugin's types. Everything the plugin does is PackagePlugin + Foundation in one file, and every check
on it is black-box (§7).

**It may write only under `pluginWorkDirectory`.** Already relied on — `_createBuildCommands`
creates three directories there (`:96-107`) — and it is where the synthesized config goes.

**Its prebuild command re-runs on every build.** Whatever the plugin writes at plan time has to be
byte-identical between runs that resolve the same graph, or Sourcery's cache
(`--cacheBasePath`, `:147-148`) is invalidated every time.

---

## 2. The rule after this spec

A target's Sourcery config declares **what to generate**: which templates, with which arguments. The
plugin supplies **where** — the target's own sources plus the recursive closure of its dependencies,
first-party and external alike, as directories; the output directory the build actually consumes, and
an error if the config names another; the absolute path of a template named by name; and the module
under test where only one module can be meant. The two meet in a config the plugin synthesizes into
its work directory by copying the author's file, expanding what it declares and appending what it
omits.

The smallest config that works becomes `templates:` plus `args:`. An author who wants today's
behaviour writes the file they write today and gets it back byte-identical.

---

## 3. Derivation

### 3.1 The closure

For the target being built:

```swift
func sourceRoots(for target: Target) -> [Path] {
  let modules: [any SourceModuleTarget] =
    ([target] + target.recursiveTargetDependencies).compactMap { $0.sourceModule }
  return modules
    .filter { $0.kind == .generic || $0.kind == .executable || $0.kind == .test }
    .map { $0.directory }
}
```

- `recursiveTargetDependencies` is the transitive closure and does **not** include the receiver, so
  the target's own directory is prepended.
- `compactMap { $0.sourceModule }` drops binary targets, system libraries and plugin targets — they
  have no Swift sources to parse.
- `.macro` and `.snippet` are filtered out: a macro target's sources are compiler-plugin code, and a
  snippet is not part of the module surface. Neither can contribute a protocol a mock is generated
  from.

### 3.2 Directories, not files

`2a2857c` enumerated `sourceFiles` per module. Three reasons this emits `directory` instead:

- **Size.** The example package's closure is RxSwift, RxRelay, RxCocoa, RxBlocking, RxTest, RIBs,
  Alamofire, Quick, Nimble and the local targets — thousands of files, one env var or one config in
  the hundreds of kilobytes. As directories it is roughly 30 lines.
- **Cache stability.** A file added to any module in the closure rewrites a file list and
  invalidates the Sourcery cache for every target. A directory list is stable until the graph
  changes.
- **It is what the author would have written.** The `sources:` entries being replaced are
  directories.

Measurement A showed overlap is harmless, so `${SOURCERY_TARGET_ExampleProjectSpmTests}/SourceryAnnotations`
may sit beside a derived entry that already contains it.

### 3.3 Determinism and dedup

The emitted list is: deduplicated by resolved path, with any path that is a descendant of another
emitted path dropped, then **sorted lexicographically**. `recursiveTargetDependencies` promises a
dependency order, not a stable one across resolutions, and §1.5 requires byte-identical output
between builds.

### 3.4 The Xcode path

`XcodeTarget` has no `recursiveTargetDependencies` and `XcodePluginContext` has no package graph. The
placeholder therefore expands, in the Xcode path, to the target's own input-file directories plus the
`.product` module directories already reachable at `:287-292` — strictly better than today's `[]` for
the `.target` case, and still not a closure. The plugin emits `Diagnostics.remark` naming what it
resolved, and the README says plainly that full derivation is SPM-only. Going further is deferred,
not dismissed — §11.2.

---

## 4. Injection: the synthesized config

### 4.1 Three ways a config says what to read

| the config | what is scanned |
| --- | --- |
| no `sources:`, `project:` or `package:` key at all | the closure — the plugin appends it (§4.6). The zero-configuration case, and fatal today (§1.4/G), so nothing changes meaning |
| `sources:` containing `- ${SOURCERY_SOURCES}` | the closure, **plus** every other entry in the list |
| `sources:` without the placeholder | exactly what is listed — today's behaviour, untouched |

The placeholder exists for the middle row, and the middle row is not hypothetical: the example's
mocks config wants the closure *and* one hand-picked subdirectory
(`${SOURCERY_TARGET_ExampleProjectSpmTests}/SourceryAnnotations`), which is a subset of a module and
therefore the one thing derivation must not decide.

It is recognised only as a **whole list item** under `sources:` or `sources.include:` (measurement D
says both forms exist), and it is deliberately **not** an env var — nothing exports
`SOURCERY_SOURCES`, so if the plugin's substitution ever failed to run, Sourcery would report an
unexpanded path rather than silently scanning less than intended.

### 4.2 The transform

Line-oriented, no YAML parsing (§1.5 forbids Yams anyway). Read the author's config as UTF-8 text and
apply, in order:

1. **Expand the placeholder.** For each line whose content, after trimming, is exactly
   `- ${SOURCERY_SOURCES}` (a trailing comment allowed), replace it with one line per derived root at
   the same indentation, each path a **double-quoted YAML scalar** with `\` and `"` escaped — paths
   contain spaces, and a DerivedData path routinely does. More than one placeholder line → each is
   expanded; measurement C says the resulting overlap is harmless.
2. **Resolve bare template names.** For each whole list item under `templates:` that names a shipped
   template rather than a path, rewrite it to the absolute quoted path (§4.5).
3. **Fill in what the config leaves out.** Append `sources:` and `output:` when the document declares
   neither them nor an equivalent, and insert `args.testable` when the module under test is
   unambiguous (§4.6).
4. **Verify `output:` when the config declares it.** A value that does not resolve to the plugin's
   output directory is a `Diagnostics.error`, not a rewrite (§4.6).
5. Every other byte is copied through, comments and all.

A config with no placeholder, no bare name, both keys present and an `args.testable` of its own comes
out byte-identical, and the plugin behaves exactly as it does today.

Rules 1 and 2 are "replace one line with N lines", rule 3 is "append a block at the end" — except for
`args.testable`, the single nested insert, whose indentation rule §4.6 states exactly — and rule 4
only reads. That is why they can be trusted without a parser: a construct the plugin does not
recognise is a construct it does not touch.

Rule 3 is the exception worth stating plainly. A duplicate top-level key is **not** an error —
Sourcery takes the last one silently (§1.4/I) — so a key appended because the plugin misread the
document would override what the author wrote, with nothing in the log. Three things bound that:
detection is a `^<key>\s*:` match at column 0, which is the shape of every config this repo ships or
documents and which a comment line cannot match (the commented-out `# package:` blocks in both
example configs are correctly invisible to it); a config in flow style (`{sources: […]}`) or split
across YAML documents is outside the contract and documented as such; and the plugin emits a
`Diagnostics.remark` naming every default it supplied, so the build log always distinguishes what
came from the file from what came from the plugin.

### 4.3 Relocation: absolute paths only

Measurement A: relative paths in a config resolve against **the config file's directory**. The
synthesized copy lives in `pluginWorkDirectory`, so a relative `templates:` or `output:` that works
today would silently resolve somewhere else.

The contract is therefore: **a config the plugin rewrites must express every path absolutely.** The
exported vars already do this — every config in the repo complies — and the two rewrites remove the
reasons to write a relative path at all: §4.5 rule 2 resolves a template file beside the config to
its absolute path, and §4.6 supplies the output directory. The plugin does not attempt to rewrite
relative paths (that needs the parser it does not have); it emits a `Diagnostics.warning` when a
spliced config contains a line matching `^\s*-?\s*[A-Za-z0-9_.]` under a path key, naming the file
and the line. A warning, not an error: the heuristic is not good enough to block a build on.

### 4.4 Where it goes

`pluginWorkDirectory/.sourceryConfigs/<original file name>` — one per discovered config, keeping the
original basename so the prebuild command's `displayName` (`:142`) still names something the author
recognises, and so a Sourcery diagnostic naming the config is traceable. The `.sourceryConfigs`
directory is created beside the three that already exist (`:96-107`), and the command's `--config`
(`:145-146`) points at the copy.

Writing happens in `_createBuildCommands`, at plan time — the same place and the same sandbox as the
existing `createDirectory` calls.

### 4.5 Naming a template: `SOURCERY_TEMPLATES`, and bare names

Today a consumer cannot portably name the templates it depends on. `${GIT_ROOT}/templates/…` works
only for a config inside this repository; a real consumer would have to hard-code
`.build/checkouts/…` or a DerivedData path — a path that moves with the resolution, and in Xcode with
the DerivedData directory.

**Finding the directory.** Walk the package graph — `context.package`, then
`package.dependencies[].package` recursively, deduplicating by `Package.id` — for the package whose
`targets` contain one named `SourcerySwiftCodegenPlugin`, and export:

```
SOURCERY_TEMPLATES = <that package's directoryURL>/templates
```

Matching on the **plugin target's name** rather than the package name is deliberate: the package's
manifest name is `SourcerySwiftCodegen`, its identity is `swift-sourcery-templates`, and a consumer
vendoring it under another directory name changes the identity but not the target name the consumer
had to write in `plugins:`. The walk is recursive because a consumer may reach the plugin through a
shared first-party package rather than declaring it itself.

**Naming the template.** With the directory known, a `templates:` entry can be a bare name:

```yml
templates:
  - Mocks
  - Component
```

Resolution, per whole list item under `templates:`, in order — the first match wins:

1. The item contains `/` or starts with `$` — a path. Left alone.
2. A file of that exact name exists **beside the author's config** — today's meaning of a relative
   entry. Rewritten to that absolute path, so the relocation of §4.3 does not break it, and a
   `Diagnostics.remark` says which file it resolved to.
3. `<templates dir>/<item>.swifttemplate` or `<templates dir>/<item>` exists, and its basename does
   not start with `_` — a shipped template. Rewritten to that absolute path.
4. Neither — left alone, and `Diagnostics.warning` names the item and lists the shipped templates.
   Sourcery then fails on it, which is the correct outcome for a typo.

Ordering 2 before 3 is what makes this backward compatible: a consumer with its own `Mocks.stencil`
beside its config keeps getting its own file. The `_` exclusion is not cosmetic —
`templates/_header.swifttemplate` is an include (`include("_header")` in all three top-level
templates), not something to run, so the resolvable set is exactly `Component`, `Mocks`, `TypeErase`.

Both `- Mocks` and `- Mocks.swifttemplate` resolve. The bare form is the documented one, and it
matches how `mock-templates` already records a template in the fingerprint: by basename
(`mockTemplatesConfigDescription`, `Commands.swift:10-13`). A config that names `Mocks` and a CLI
invocation that passes an absolute path to the same file produce the same `config:` line, so the two
paths describe generation identically.

**Why not name the template from the config's filename** — `.Sourcery.Mocks.yml` implying
`Mocks.swifttemplate`: a config can drive several templates and Sourcery writes one
`<Template>.generated.swift` per entry (§1.4/F), so a filename cannot carry the list. The discovery
regex (`:190`) also accepts any name, and the CocoaPods-era configs used `.sourcery-mocks.yml`, so
giving the middle segment meaning would reinterpret files that already exist. Rejected outright, not
kept as a fallback (D9): only `templates:` entries are acted on, and a config that omits the key has
nothing to generate and says so.

**Xcode.** `XcodePluginContext` has no package graph, so `SOURCERY_TEMPLATES` is not exported and
rule 3 never fires; a bare name warns and fails. Xcode consumers keep writing paths, and the
`Diagnostics.remark` says why.

### 4.6 The keys the plugin fills in

`sources:` and `output:` are mandatory today — a config missing either fails to load (§1.4/G,
§1.4/H) — so supplying them cannot change what an existing config means. That makes the
zero-configuration case worth serving: a config that says only *what to generate* is a complete
config. The smallest useful one is four lines:

```yml
# .Sourcery.Mocks.yml — beside the test target
templates:
  - Mocks
```

| key | absent | present |
| --- | --- | --- |
| `sources:` (or `project:` / `package:`) | the derived closure is appended, exactly as the placeholder would have expanded it | untouched — the author is naming inputs deliberately |
| `output:` | the plugin's `generatedFilesDir` is appended, as an absolute quoted path | **verified, and a mismatch is fatal** — see below |
| `args.testable` | the module under test, when there is exactly one | untouched |

`project:` and `package:` are checked alongside `sources:` because Sourcery accepts any of the three
as the input declaration (§1.4/G) — appending sources to a config that legitimately uses `package:`
would override a deliberate choice, silently (§1.4/I).

**`output:` is the plugin's, and disagreeing about it is an error.** A prebuild command's outputs are
collected from the `outputFilesDirectory` it declared (`:154`); a file written anywhere else is
written and then ignored, so the target compiles without it and the failure surfaces as a missing
type, far from its cause. The plugin therefore does not merely default the key — when the config
supplies one, it expands `${…}` in the value from the env map it is about to pass, standardizes it,
and compares:

- equal to `generatedFilesDir` → left as written (this is what `${SOURCERY_OUTPUT_DIR}` resolves to).
- anything else, a subdirectory included → `Diagnostics.error` naming the config, the resolved path
  and the required one. Loud, not silently rewritten: rewriting would hide an author's intent, and
  the intent is wrong in a way only they can fix.
- an object-form `output:` (Sourcery accepts a mapping with `path:`, per §1.4/H's message) → the
  nested `path:` scalar is checked the same way; a shape the line rules cannot read is a
  `Diagnostics.warning` saying the output was not verified.

Appending the absolute path rather than `${SOURCERY_OUTPUT_DIR}` is deliberate: the synthesized file
is the plugin's own, and a literal path is one less expansion between the plugin and the directory
the build actually consumes. The env var keeps being exported for configs that write it themselves.

**`args.testable`, when the answer is unambiguous.** For a target of kind `.test`, the candidates are
its **direct** `.target(_)` dependencies whose module is in the root package and is not itself a test
module. Exactly one candidate → the plugin inserts `testable: [<moduleName>]` under `args:`. Zero, or
two or more → nothing is inserted, and a `Diagnostics.remark` names the candidates so the author
knows why they have to write it.

Direct dependencies, not the closure, and that distinction is load-bearing: §6.1 adds
`ExampleProjectSpmCore` beneath `ExampleProjectSpm`, so the closure has two root-package modules
while the direct dependencies still have one. The module a test target is testing is the one it
depends on; a module it reaches only through that one is not. Restricting candidates to `.target`
dependencies keeps first-party modules from *other* packages out, which is the same judgement and
also the shape every example has.

The insertion is the one nested edit in §4.2, so its line rule is stated exactly:

- No top-level `args:` → append `args:` with a two-space-indented `testable:` block at the end.
- `args:` present → take the indentation of the first following line that is neither blank nor a
  comment and is indented further than `args:` itself, and insert `testable:` at that indentation
  immediately after the `args:` line. Matching the siblings' indentation is what keeps the mapping
  parseable.
- `args:` present with a `testable:` already under it, or written in flow style (`args: {…}`), or
  with no more-indented line following → nothing is inserted, and the plugin says so.

A `testable` arg the template ignores is harmless — `Component` and `TypeErase` never read it — so
the rule keys off the target's kind rather than the template's name.

### 4.7 Several configs, several templates

Both multiplicities already work and the naming rules are built for them:

- **Per target**, the plugin discovers every file in the target's directory matching
  `[^/:]*\.sourcery([^/:]*)\.yml$` (`:83-91`, `:190`) and emits one prebuild command per config
  (`:113-127`). Non-recursive, so configs live at the target root.
- **Per config**, `templates:` may list several, and Sourcery writes one
  `<Template>.generated.swift` per entry into the output directory (§1.4/F).

The adopter shape this is meant to serve:

```
Sources/MyModule/.Sourcery.Components.yml       templates: [Component, TypeErase]
Tests/MyModuleTests/.Sourcery.Mocks.yml         templates: [Mocks], args.testable: [MyModule]
```

The split is forced by the generated code's audience — mocks belong to the test target, type erasures
and Components to the module — and the plugin already puts each target's output on that target's
compile path. Splitting *within* a target, on the other hand, is a choice between one config naming
two templates and two configs naming one each; they generate the same files.

One sharp edge to keep: every config of a target shares one `generatedFilesDir` (`:106`), so two
configs of the same target that name the same template write the same
`<Template>.generated.swift` and the second silently wins. The plugin detects that at plan time — the
resolved template basenames per target are known once rule 2 of §4.2 has run — and emits a
`Diagnostics.error` naming both configs. The related unknown — those configs also share one
`--cacheBasePath` and one `--buildPath` — is measured by the fixture rather than argued about (§7).

---

## 5. What the plugin does *not* take over

The question this spec had to answer: with sources derived, should the plugin also supply
`@testable import` / `import` module names, lint exclusions and the rest? **No.** The synthesized
config carries them through unread. Here is the reasoning per option, because "the plugin could
compute it" is true of several of them and still wrong. The line between the two columns is not
"could the plugin work it out" but **"is there one right answer"**: a derivation that is right most
of the time is worse than no derivation, because the config no longer says what happens.

| option | derivable? | verdict |
| --- | --- | --- |
| `args.testable` | When the test target directly depends on exactly one root-package non-test module — yes | **Defaulted when unambiguous** (§4.6). One candidate is not a guess, it is the answer. Two or more and the plugin inserts nothing and names them: only the author knows which module the mocks belong to, and a wrong guess emits `@testable import` of a module the file never references — a warning in every consumer build. |
| `args.import` | No | **Author's.** The imports a generated file needs are a function of the types appearing in the emitted signatures, not of the dependency list. Importing the closure would emit `import Quick` into a mocks file: unused-import noise in a repo whose fast lane gates on zero diagnostics. |
| `args.excludedSwiftLintRules` | No | **Author's.** Consumer lint policy. |
| `templates` | The *path*, yes; the *choice*, no | **Author's, with the path resolved.** Which template runs is the whole reason a target carries several configs. §4.5 resolves a bare name to the shipped file so the choice can be written portably; the choice itself stays authored, and a config that omits `templates:` has nothing to generate. |
| `output` | Yes | **The plugin's** (§4.6). Outputs are collected only from `outputFilesDirectory` (`:154`), so there is exactly one right answer: supplied when omitted, and a config that names a different one fails loudly rather than generating into a directory nothing reads. |
| `sources` | Yes | **Derived** — appended when the config declares no inputs, expanded in place where the placeholder appears (§4.1). |

The shape this lands on: a config says *what to generate*, and every part of *where to read and where
to write* has a defensible single answer the plugin fills in. What the plugin never does is guess at
an option whose right value depends on what the author meant — and where an option is unambiguous in
one package and ambiguous in the next, it fills in only the first case and says why in the second.

---

## 6. Examples

### 6.1 A third target — the transitive first-party case

The pitfall CONTRIBUTING documents ("Sourcery only knows the declarations it parses") has no example
reproducing it. Add `Examples/ExampleProjectSpm/Sources/ExampleProjectSpmCore/`:

```swift
// ExampleProjectSpmCore — no annotation here; this module is not scanned today.
public protocol Persisting {
  func save(_ data: Data, key: String) throws
}
```

`ExampleProjectSpm` depends on it and refines it:

```swift
// sourcery: CreateMock
protocol ProfilePersisting: Persisting {
  var profileID: String { get }
}
```

`ExampleProjectSpmTests` depends on `ExampleProjectSpm` only — so `Persisting` is reachable exactly
one level deeper than any exported var, which is the case with no expressible workaround today. It is
also the case that separates §4.6's two candidate rules: the test target's *closure* now holds two
root-package modules, its *direct* dependencies still hold one, and `args.testable` keeps defaulting
to `ExampleProjectSpm` because D11 chose the latter.

**Red control:** on today's plugin the generated `ProfilePersistingMock` carries `profileID` and not
`save`, and the test target fails to compile with "type 'ProfilePersistingMock' does not conform to
protocol 'ProfilePersisting'" — the failure mode CONTRIBUTING describes as surfacing only in a
consumer's build. After this spec it compiles, and a spec in
`SwiftSourceryTemplatesMocksSpec.swift` asserts `saveCallCount` / `saveArgs` record.

### 6.2 The transitive external case

Drop this line from `.Sourcery.Mocks.yml`:

```yml
  - ${SOURCERY_TARGET_ExampleProjectSpm_DEP_RIBs_MODULE_RIBs}
```

The existing `RIBs+SourceryAnnotations.swift` extensions keep generating their mocks only if the
derived closure really reaches an external checkout. The existing RIBs specs are the assertion; no
new test needed.

### 6.3 Consumer-shaped configs

The examples stop being the only configs that could have been written the way they are. Both drop
`${GIT_ROOT}/templates/…` for a bare template name; `GIT_ROOT` keeps being exported, since it is
public contract and a consumer may still want it.

`.Sourcery.Mocks.yml`, beside the test target — the mixed case, keeping one hand-picked subset:

```yml
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_TARGET_ExampleProjectSpmTests}/SourceryAnnotations
templates:
  - Mocks
args:
  import: [ … unchanged … ]
```

Four `sources:` entries become two, `output:` and `args.testable` disappear (§4.6), and the remaining
hand-written source entry is there because the author wants a *subset* of a directory — the one thing
derivation must not decide. Dropping `testable` rather than leaving it explicit is deliberate: it
puts D11's default on the full lane, where a change to the candidate rule shows up as a compile
failure in the specs rather than as a passing test that no longer proves anything.

`.Sourcery.TypeErase.yml`, beside the sources target — the zero-configuration case, since it scans
only its own target and the closure is a superset of that:

```yml
templates:
  - TypeErase
args:
  import: [RIBs, RxSwift, UIKit]
  excludedSwiftLintRules: [ … unchanged … ]
```

Both files then read as *what to generate* and nothing else, which is the claim §2 makes.

To also cover §4.7's multiplicity in something CI runs, the sources-side config additionally names
`Component`, generating `Component.generated.swift` beside `TypeErase.generated.swift` from one
config — the two-templates-one-config shape, which nothing exercises today.

### 6.4 The cost to measure

The derived closure is much bigger than what the example lists today: RxSwift, RxCocoa, RxRelay,
RxBlocking, RxTest, Alamofire, Quick, Nimble and RIBs, in full. Sourcery parses all of it on a cold
cache. **Record the example lane's wall time before and after** and put both numbers in the
CHANGELOG entry. If the increase is material, the mitigations in order are: `sources.exclude` in the
example config; a `${SOURCERY_SOURCES_LOCAL}` variant scoped to the root package (§11.1); leaving the
external modules to explicit vars, which still works.

This is the one place the spec's approach can fail on its merits rather than on its mechanics, so it
is measured rather than argued.

---

## 7. Checks

The plugin cannot be imported by a test target (§1.5), so every check is black-box over a fixture
package.

New lane, `Checks/run-plugin-checks.sh`, over `Checks/PluginFixture/` — a package with a three-level
target chain (`Leaf` ← `Middle` ← `App`), an external-looking path dependency, and four configs, one
per shape §4.1 and §4.6 define:

| gate | what it proves |
| --- | --- |
| **splice** | after `swift build`, the synthesized config under `.build/plugins/…/.sourceryConfigs/` contains one quoted directory line per module in the closure, sorted, with `Leaf` present — the case no env var can express |
| **passthrough** | every other line of the placeholder config, comments included, is byte-identical to the source file |
| **defaults** | a config carrying only `templates:` comes out with a `sources:` block holding the closure and an `output:` holding the absolute output directory, and generates |
| **no-defaults** | a config declaring both keys gets neither appended — and one declaring `package:` instead of `sources:` gets no `sources:` block (§1.4/G, the silent-override case of §1.4/I) |
| **wrong output** | a config whose `output:` resolves anywhere but the plugin's directory fails the build with a `Diagnostics.error` naming both paths — the red control for D12 |
| **testable** | the fixture's test target, with one direct root-package dependency, gets `testable: [<module>]` inserted at the existing `args:` indentation; a second fixture target with two gets nothing and a remark; a config that already has `testable` is untouched; a non-test target never gets it |
| **bare name** | `- Mocks` resolves to the shipped template; a template file beside the config wins over the shipped one of the same name (§4.5 rule 2 before rule 3); an unknown name warns and fails |
| **collision** | two configs of one target naming the same template is a `Diagnostics.error`, not a silent overwrite (§4.7) |
| **determinism** | a second `swift build` with no source change leaves every synthesized config byte-identical (§1.5, cache stability) |
| **no-placeholder** | a config with none of the above is copied verbatim and generates what it generates today |
| **generation** | the generated mock for the `Leaf`-refining protocol carries the inherited requirement — the §6.1 failure, at fast-lane speed |

`Checks/run-checks.sh` and `run-cli-checks.sh` are untouched: no template and no CLI behaviour
changes here. CI gains the plugin lane beside `checks` and `cli` (it needs no simulator); the
`example-project` lane keeps covering the real thing.

The fixture also carries the **shared-cache measurement**. A target with two configs is the shape
§4.7 encourages and nothing has ever run: both prebuild commands are handed the same
`--cacheBasePath` and `--buildPath` (`:96-102`, `:147-150`). Build that target repeatedly, cold and
warm, and record whether the two runs interfere — a corrupted cache, a "recovering with a full
rebuild" line, or nothing at all. The answer decides whether each config needs its own cache
subdirectory, which costs a cold cache per config; until it is measured the spec claims nothing about
it.

---

## 8. Phasing

Each step is a commit that stands on its own and leaves `master` green.

1. **Template naming** (§4.5): the graph walk, `SOURCERY_TEMPLATES`, and bare-name resolution.
   Independently useful, changes no existing config's meaning, and the fixture only needs one config.
   Examples adopt the bare form in the same commit; `GIT_ROOT` stays exported.
2. **Derivation, the placeholder and the defaults** (§3, §4.1-4.4, §4.6). The plugin change, the
   fixture package and `Checks/run-plugin-checks.sh`, plus the CI lane. Carries the `output:`
   verification (D12) and the `args.testable` default (D11) — both are §4.6 and both need the same
   line machinery. No example config uses any of it yet, so the full lane must be unchanged: that is
   the backward-compatibility gate.
3. **The collision diagnostic and the cache measurement** (§4.7, §7). Small, and both want the
   preceding steps: the diagnostic is stated in terms of resolved template names, and the measurement
   needs a fixture target carrying two configs.
4. **The example adopts it** (§6.1-6.3). New `ExampleProjectSpmCore` target, the refining protocol,
   the dropped RIBs line, the two configs reduced to what they generate, the added `Component`
   entry, the new spec assertions, and the before/after wall-time measurement.
5. **Docs.** README's plugin section rewritten around the three config shapes; CONTRIBUTING's
   "Sourcery only knows the declarations it parses" pitfall gains "on the plugin path,
   `${SOURCERY_SOURCES}` closes this"; a CHANGELOG entry carrying both wall-time numbers.
6. **The Xcode path** (§3.4) — degrade safely and say so in the README. The exploration of whether
   it can do better is deferred (§11.2); what this step owes is that an Xcode consumer's build does
   not break and the log says which features are SPM-only.

Steps 1-3 are worth landing even if 4 measures badly (§6.4): everything before the example is opt-in,
and a consumer with a small graph benefits regardless.

---

## 9. Decisions

- **D1 — Line rules, not a YAML parser.** A plugin cannot depend on a library (§1.5, measured), so a
  parser would have to be hand-written; a hand-written YAML parser deciding what a consumer's config
  means is a much larger liability than a line-level substitution. Costs, all three real: the
  placeholder and a bare template name must each be a whole list item; §4.3's relative-path contract
  cannot be enforced properly; and a top-level key is detected by a column-0 line match, which a
  flow-style or multi-document config defeats — silently, because a duplicate key is last-wins
  (§1.4/I). That last one is why §4.2 rule 3 logs what it appended.
- **D2 — Directories, not the file list of `2a2857c`.** §3.2. Smaller, cache-stable, and the shape
  the entries being replaced already had.
- **D3 — Absolute paths are a contract, and the check is a warning.** §4.3. Erroring on a heuristic
  would block builds the plugin misread; the three configs in this repo already comply.
- **D4 — The plugin supplies where, the config says what.** §5. `sources` and `output` have one
  defensible answer each; `args.import`, the lint exclusions and the choice of template do not, and
  stay authored. The test is not "can the plugin compute it" but "is there one right answer" —
  applied per package, not per option, which is what D11 turns on.
- **D8 — A template is named by name, not by path or by the config's filename.** §4.5. A path is
  what a consumer cannot write portably, and the config's filename cannot carry a list — a config may
  name several templates and Sourcery writes one file per entry (§1.4/F). Naming by basename also
  matches what `mock-templates` records in the fingerprint (`Commands.swift:10-13`), so the plugin
  path and the CLI path describe generation identically. A file beside the config still wins, which
  is what keeps the rule backward compatible.
- **D9 — The config's filename is never load-bearing.** The discovery regex (`:190`) accepts any
  `*.sourcery*.yml`, and the CocoaPods-era configs used `.sourcery-mocks.yml`; giving the middle
  segment meaning would reinterpret files that already exist, and would make a rename change what a
  build generates. The filename names the file, and nothing else — not even as a fallback for a
  config that omits `templates:`, which is simply an error. Only `templates:` entries are acted on.
- **D10 — Defaults are appended, not merged.** §4.6. A missing `sources:` or `output:` is fatal today
  (§1.4/G, §1.4/H), so supplying them cannot change an existing config; and appending a block is a
  transform the plugin can perform correctly without understanding the document, which merging into
  an existing key is not. `args.testable` is the single exception and pays for it with an explicit
  indentation rule and three cases where it declines to act.
- **D11 — `args.testable` defaults from the *direct* dependencies, not the closure.** §4.6. The
  module a test target tests is the one it depends on; one it reaches only through that module is
  not. The distinction is not academic — §6.1's new `ExampleProjectSpmCore` makes the closure
  ambiguous and leaves the direct dependencies unambiguous, so a closure-based rule would stop
  defaulting exactly when the example got more realistic.
- **D12 — A wrong `output:` fails the build.** §4.6. Generating into a directory the build does not
  collect from produces a target that compiles without the generated file; the error surfaces as a
  missing type with nothing pointing at the config. The plugin knows the right answer, so it says so
  rather than silently rewriting the author's value — a rewrite would make a deliberate-looking line
  a lie.
- **D5 — Every existing env var keeps its name and value.** A config with no placeholder is copied
  verbatim. This spec adds capability and removes none, so no consumer has to change anything.
- **D6 — `mock-templates` is unchanged.** Its doc comment (§1.2) commits it to policy-freedom, and a
  caller who wants derivation has a shell. Making the CLI resolve a package graph would mean
  shelling out to `swift package dump-package` from a tool whose whole value is that it needs no
  toolchain at validation time.
- **D7 — The placeholder is not an env var.** §4.1. An unexpanded `${SOURCERY_SOURCES}` fails loudly;
  an unexported env var expands to nothing and silently scans less.

---

## 10. Non-goals

- Fingerprinting on the plugin path. The plugin runs `sourcery` directly (`:143-144`); routing it
  through `mock-templates generate` would give plugin-generated files a provenance block, and it is
  a separate change with its own design (the output would land in DerivedData, where a fingerprint
  proves nothing a rebuild does not).
- Any template change. This spec moves no generated byte except by scanning more sources.
- CocoaPods. Retired at `4b1d0bb`.
- Teaching Sourcery about SPM. Its `package:` config key exists (both example configs carry it
  commented out) and would need the engine to run SwiftPM itself — the thing the plugin sandbox is
  there to prevent.

---

## 11. Open questions

1. **Does the full closure cost too much?** §6.4. Measured in phase 4, and the answer decides whether
   `${SOURCERY_SOURCES_LOCAL}` (root-package modules only) ships beside the full variant or not at
   all. The only question here that can invalidate an approach rather than tune one.
2. **The Xcode path.** Deferred, and worth exploring later rather than closing now. `XcodeTarget` has
   no `recursiveTargetDependencies` and `XcodePluginContext` no package graph, so §3.4 degrades to
   the target's own input directories plus the product modules already reachable — better than
   today's `[]`, not a closure. Two threads when it is picked up: whether the checkouts directory can
   be reached from the resolved artifact path well enough to export `SOURCERY_TEMPLATES`, and whether
   a small committed `.xcodeproj` fixture is worth its maintenance — with the CocoaPods example gone
   there is no coverage of `XcodeBuildToolPlugin` at all.
3. **The object form of `output:`.** §4.6 checks a nested `path:` scalar and warns on any other
   shape. Nothing in this repo has ever written one, so the shape is unmeasured; if a consumer turns
   up using `link:` to add generated files to an Xcode target, the check needs revisiting rather than
   extending.

Resolved while drafting, and recorded where they belong rather than here: `args.testable` defaults
when unambiguous (D11, §4.6); a config that names the wrong `output:` fails the build (D12, §4.6);
the config's filename is never load-bearing and only `templates:` entries are acted on (D9, §4.5);
the shared per-target cache and build directories are measured by the fixture rather than argued
(§7).
