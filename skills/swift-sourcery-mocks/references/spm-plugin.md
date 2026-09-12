# The build-tool plugin, in full

`SourcerySwiftCodegenPlugin` is a prebuild plugin. It runs before the target compiles, reads every
`*.sourcery*.yml` config it finds for that target, rewrites a copy of each one with the paths the
build system actually uses, and runs the generator over it. Nothing is written into the source tree.

## What a config must say, and what the plugin supplies

A config says *what to generate*. The plugin supplies *where*.

```yml
# Sources/MyModuleTests/.Sourcery.Mocks.yml
templates:
  - Mocks
```

That is complete. The plugin appends `sources:`, appends `output:`, and — under the one condition
below — `args.testable`. Everything else in the file is carried through unread.

A target may carry several configs; each generates into a directory of its own. Two configs of one
target naming the same template are refused at plan time, naming both files.

## The three ways a config says what to read

| the config | what is scanned |
| --- | --- |
| no `sources:`, `project:` or `package:` key | the closure, appended by the plugin |
| `sources:` containing `- ${SOURCERY_SOURCES}` | the closure, plus every other entry in the list |
| `sources:` without the placeholder | exactly what is listed, and the plugin appends nothing |

`${SOURCERY_SOURCES}` is a placeholder the plugin expands, not an environment variable. Nothing
exports it, so a substitution that failed would make the generator report an unexpanded path rather
than quietly scan less than the config meant.

On the SwiftPM path it expands to the target's own sources plus the recursive closure of its
dependencies, first-party and external alike, one directory per module. That closure is what lets a
mock carry the requirements its protocol inherits from a module the target reaches only through
another package.

A config that sets `project:` or `package:` is left entirely alone: the plugin appends no `sources:`
over it and it fails or succeeds on its own terms.

## Naming a template

A `templates:` entry that is a bare name is resolved in this order, first match winning:

1. it contains `/` or starts with `$` — a path, left as written;
2. a file of that exact name sits beside the config — a project's own `Mocks.swifttemplate` keeps
   winning;
3. a template shipped by this package;
4. none of the above — the plugin warns, lists the shipped templates, and the generator then fails
   on the name.

Step 3 searches three locations, first directory on disk winning, and the build log names the one
that answered: the package in the dependency graph, the plugin's own source location three
components up, and the artifact bundle `Package.swift` pins. The last two read no package graph,
which is why a bare name resolves in an Xcode project too.

The shipped names are `Mocks`, `TypeErase` and `Component`.

## The exported variables

| variable | value |
| --- | --- |
| `SOURCERY_SOURCES` | *not a variable* — the placeholder above |
| `SOURCERY_TEMPLATES` | the shipped `templates/` directory |
| `SOURCERY_OUTPUT_DIR` | the directory this config's output is collected from |
| `SOURCERY_PACKAGE` | the root package directory |
| `SOURCERY_PROJECT` | the project directory, in an Xcode project |
| `SOURCERY_TARGET_<target>` | that target's source directory |
| `SOURCERY_TARGET_<target>_DEP_<target>` | a directly-depended target's source directory |
| `SOURCERY_TARGET_<target>_DEP_<product>_MODULE_<module>` | a module of a directly-depended product |
| `SOURCERY_TARGET_<target>_DEP_<product>_TARGET_<target>` | a target of a directly-depended product |
| `GIT_ROOT` | `git rev-parse --show-toplevel` from the package directory |

The `_DEP_` variables name a target's *direct* dependencies only, one level deep. Reaching further
is what `${SOURCERY_SOURCES}` is for; reach for a `SOURCERY_TARGET_*` variable only to name a
subdirectory the closure does not cover, such as a directory of annotation-only extensions:

```yml
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_TARGET_MyModuleTests}/SourceryAnnotations
```

Every path in a config must be absolute. The plugin runs a copy of the config from its own work
directory, and a relative path in a generator config resolves against the config file's own
directory. The plugin warns when it sees one and does not rewrite it.

## Where the output goes

`output:` belongs to the plugin. A prebuild command's outputs are collected only from the directory
it declared, so a file written anywhere else is generated and then ignored — the target compiles
without it and the failure surfaces as a missing type far from its cause. Three outcomes:

- omit `output:` — the plugin supplies it;
- `output: ${SOURCERY_OUTPUT_DIR}` — the same directory, written out;
- any other directory — the build fails, naming both paths.

## Finding the generated file on disk

It is a build product under the build root, not a file in the package tree, and nothing writes a
copy or a pointer into the tree — a prebuild command may write only inside the directory the plugin
declared. Both lanes put it under one path segment, `SourcerySwiftCodegenPlugin/.generatedFiles/`:

```
# SwiftPM
<build>/plugins/outputs/<package, lowercased>/<Target>/destination/
    SourcerySwiftCodegenPlugin/.generatedFiles/<config stem>/<Template>.generated.swift

# Xcode
<DerivedData>/<Project>-<hash>/Build/Intermediates.noindex/BuildToolPluginIntermediates/
    <project>.output/<Target>/SourcerySwiftCodegenPlugin/.generatedFiles/<config stem>/<Template>.generated.swift
```

The config stem is the config's file name without its leading dot and its extension, so
`.Sourcery.Mocks.yml` writes into `.generatedFiles/Sourcery.Mocks/`. One command finds the files on
either lane:

```bash
find "$BUILD_ROOT" -path '*/SourcerySwiftCodegenPlugin/.generatedFiles/*' -name '*.generated.swift'
```

`$BUILD_ROOT` is `.build` for a package. For an Xcode project it is derived data, which may be
relocated, so read it rather than assume it:

```bash
xcodebuild -project X.xcodeproj -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILD_DIR = /{print $2}'
```

**The build log names the directory outright.** For every config the plugin supplies `output:` for,
it remarks:

```
.Sourcery.Mocks.yml: the plugin supplied sources: …; output: /abs/path/…/.generatedFiles/Sourcery.Mocks.
```

`swift build -v` prints it; in Xcode it is in the build log under the target's plugin step. Read it
when the `find` comes back empty — it says whether the plugin ran at all.

## `args.testable`, and the arguments that stay yours

`args.import`, `args.excludedSwiftLintRules` and the choice of template are carried through unread.
`args.testable` is the one exception, and only where the answer is unambiguous: for a test target
with exactly one direct dependency on a module of the same package, the plugin inserts
`testable: [<module>]`. With none, or with two or more, it inserts nothing and names the candidates
in the build log — write the key yourself in that case:

```yml
templates:
  - Mocks
args:
  testable: [MyModule]
  import: [Foundation]
```

A Component is production code, so its config takes `import:`, not `testable:`.

## Several templates from one config

```yml
# Sources/MyModule/.Sourcery.Components.yml
templates:
  - Component
  - TypeErase
```

One `<Template>.generated.swift` is written per entry.

## Xcode projects

The plugin runs through `XcodeBuildToolPlugin` there, and that API is handed no package graph. The
config copy, the rewrite, the appended defaults, the `output:` check, the passthrough and template
name resolution are the same implementation as on the SwiftPM path. Four things differ:

| | SwiftPM package | Xcode project |
| --- | --- | --- |
| `${SOURCERY_SOURCES}` expands to | the target's own sources plus the recursive closure of its dependencies | the target's own input-file directories, and nothing else |
| a config is looked for in | the target's own source directory | every first-level directory under the project root that holds one of the target's input files |
| exported variables | `SOURCERY_PACKAGE`, `SOURCERY_TARGET_*`, the `_DEP_` shapes, `GIT_ROOT`, `SOURCERY_TEMPLATES`, `SOURCERY_OUTPUT_DIR` | `SOURCERY_PROJECT`, `GIT_ROOT`, `SOURCERY_TEMPLATES` and `SOURCERY_OUTPUT_DIR` only |
| `args.testable` | inserted under the condition above | never inserted |

The dependency edges an Xcode target reports are empty for a package product dependency and for a
sibling target in the same project, which is why there is no closure to derive and no
`SOURCERY_TARGET_*` variable to name. Name every further directory yourself, as an absolute path
under `${SOURCERY_PROJECT}`:

```yml
templates:
  - Mocks
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_PROJECT}/Libraries/Kit/Sources
```

Add the plugin to a target under **Build Phases → Run Build Tool Plug-ins**, and put the config in
the directory that holds the target's own sources.

## Reading what the plugin did

The plugin writes its whole derivation to the build log: every exported variable, every default it
supplied, every template name it resolved and the route that answered. `swift build -v` shows the
remarks as well as the warnings. When a generated type is missing, read that log before changing the
config — it says what was scanned and where the output went.
