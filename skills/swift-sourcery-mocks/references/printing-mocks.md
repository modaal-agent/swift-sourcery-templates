# Printing a mock without building

`scripts/print-mocks.sh`, beside `SKILL.md`, prints what `SourcerySwiftCodegenPlugin` generates for one
target and compiles nothing. It edits no file in the repository.

## The command

```bash
"${CLAUDE_SKILL_DIR}/scripts/print-mocks.sh" <Target> [<Protocol> ...]
```

Claude Code replaces `${CLAUDE_SKILL_DIR}` with the directory holding `SKILL.md`; in another agent,
write that directory's path in its place. Run it from the directory holding `Package.swift`, or from
the one holding the `.xcodeproj` or `.xcworkspace`. `<Target>` is the target that applies the plugin
and carries the config: the test target, for mocks.

## What it prints

With protocol names, each protocol's mock — its `// MARK: - <Protocol>` line through the class's
closing brace — and a blank line:

```
// MARK: - DataService
// Members are the requirement's declared name plus a suffix — …
final class DataServiceMock: DataService {
…
}
```

A name with no mock prints `// <Protocol>: no mock generated for <Target>`; the other names still
print, and the script exits 1.

With no protocol name, every `*.generated.swift` of the target — mocks, type erasures, Components —
each after a `// <path>` line and followed by a blank line. The body is the file the target compiles,
byte for byte.

## SwiftPM packages

The script runs

```bash
swift build --target <Target> --print-manifest-job-graph > /dev/null
```

which plans the build: SwiftPM runs the plugin's prebuild command and compiles nothing. It then prints
`.build/plugins/outputs/*/<Target>/destination/SourcerySwiftCodegenPlugin/.generatedFiles/*/*.generated.swift`.
An agent that cannot run the script runs that command and reads those files.

- **It runs while the module does not compile.** The plugin writes the generated file and the command
  exits 0.
- **It picks up an edit inside an existing file.** A plain `swift build` after such an edit reuses
  its last plan and leaves the generated file as it was; planning again regenerates it.
- **A package whose `platforms:` declares no macOS** cannot be planned for the Mac once it depends on
  the plugin. On `depends on the product 'SourcerySwiftCodegenPlugin' which requires macos` the
  script plans for the iOS simulator instead, adding
  `--triple "$(uname -m)-apple-ios-simulator" --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"`.
- **`SCRATCH_PATH`** names the build directory when it is not `.build`, as `--scratch-path` does.
- **Inside another sandbox** — `sandbox-exec`, or an agent's own — SwiftPM cannot start its sandbox, and
  the plan fails with `sandbox_apply: Operation not permitted`, or with `Plugin ended with exit code 71`
  once SwiftPM has the package's manifest cached. The script then prints
  `print-mocks: SwiftPM could not start its sandbox; planning again with --disable-sandbox` and plans
  again with that flag. Set `PRINT_MOCKS_DISABLE_SANDBOX=1` to pass the flag from the first plan. Running
  the command by hand, add `--disable-sandbox`.
- **That sandbox has to allow writes** to the build directory and to `TemporaryItems` under the
  directory `getconf DARWIN_USER_TEMP_DIR` prints; SwiftPM writes there. When the plan fails with
  `Operation not permitted` on another path under that directory, the plugin release in use does not
  give Sourcery a `TMPDIR` under the build directory: allow that path, or update the release.
- **A plan that downloads the Sourcery artifact bundle** — the first in a checkout whose build directory
  does not hold it, when SwiftPM's cache does not either — fails inside such a sandbox with
  `failed downloading '…artifactbundle.zip' … Operation not permitted`, with or without
  `--disable-sandbox`: SwiftPM writes the download under that directory, outside `TemporaryItems`. Run
  `swift package resolve` outside the sandbox once, then print.

## Xcode projects

`xcodebuild` has no action that plans without building, so the script re-runs the Sourcery engine on
the configs the plugin wrote at the target's last build, with `output:` pointed at
`<DerivedData>/Build/Intermediates.noindex/PrintMocks/<Target>/`. The build's own generated file is
left as it was.

- **Build the target once first**, in Xcode or with `xcodebuild`. Until then there is no config to
  re-run.
- **A run reads the sources as they are now**, in the directories the last build's config lists: an
  edit to a protocol shows without a build. A new source directory, a changed config or a new package
  dependency shows after the next build.
- **The derived data** is the directory under `~/Library/Developer/Xcode/DerivedData` whose
  `info.plist` names a project under the working directory and whose configs for `<Target>` were
  written last.

| variable | set it when | to |
| --- | --- | --- |
| `DERIVED_DATA` | the build used `-derivedDataPath`, or the script picked another build of the project | that derived data directory |
| `DERIVED_DATA_ROOT` | derived data is kept under another root | that root |
| `SOURCERY_PROJECT` | the `.xcworkspace` is not in the directory holding the `.xcodeproj` | the directory holding the `.xcodeproj` |
| `PRINT_MOCKS_ENGINE` | the script finds no engine — the build used `-clonedSourcePackagesDirPath`, or the config names its template under `${GIT_ROOT}` | the `sourcery/bin/sourcery` under that `SourcePackages/artifacts/` |

## When it fails

| output | what to do |
| --- | --- |
| `print-mocks: <Target> generated no file — does it apply SourcerySwiftCodegenPlugin and carry a *.sourcery*.yml config?` | name the target that applies the plugin, and put a config in its source directory (SKILL.md §"The plugin lane") |
| `// <Protocol>: no mock generated for <Target>`, then `print-mocks: <count> of <count> protocols have no mock in <Target>'s generated files` | the protocol carries no `ProtocolMock`, sits outside every scanned directory, or is spelled differently. Run without protocol names and read what was generated |
| `print-mocks: planning <Target> failed`, after SwiftPM's errors | the plugin's `error:` line names the config line to fix — a template name that does not resolve, or an `output:` the build does not collect from ([troubleshooting.md](troubleshooting.md)) |
| `print-mocks: planning <Target> for the iOS simulator failed`, after SwiftPM's errors | build the test target with `xcodebuild` for a simulator and read its `.generatedFiles/` ([spm-plugin.md](spm-plugin.md)) |
| `print-mocks: no configs the plugin synthesized for <Target> under <directory> — build <Target> once, or set DERIVED_DATA` | build the target once, or set `DERIVED_DATA` to the derived data the build used |
| `print-mocks: <directory> holds no config` | build the target again; the plugin writes its configs at every build |
| `print-mocks: no Sourcery engine found for <DerivedData> — set PRINT_MOCKS_ENGINE` | set `PRINT_MOCKS_ENGINE` as the table above says |
| `print-mocks: the engine failed on <config> for <Target>`, after Sourcery's error | a `does not exist or is not readable` path under the project means `SOURCERY_PROJECT` is wrong; any other error is the config's, and the next build fails on it too |
| `print-mocks: run from the directory holding Package.swift or the .xcodeproj` | change to that directory, or set `DERIVED_DATA` |
