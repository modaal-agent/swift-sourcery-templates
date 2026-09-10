# The `mock-templates` CLI

For a repository that commits its generated mocks: generate once, commit the file, and let CI prove
it current without running the generator. `mock-templates` wraps the generator invocation and writes
a fingerprint block above the generated body.

## Where the binaries come from

The release artifact bundle carries the generator engine, the `templates/` tree and the CLI at one
tag, so there is no pair of versions to keep matched:

```bash
VERSION=<newest tag>          # git ls-remote --tags https://github.com/modaal-agent/swift-sourcery-templates.git | tail -1
BASE=https://github.com/modaal-agent/swift-sourcery-templates/releases/download/$VERSION
curl -fsSLO "$BASE/swift-sourcery-templates-$VERSION.artifactbundle.zip"
curl -fsSLO "$BASE/swift-sourcery-templates-$VERSION.artifactbundle.zip.sha256"
shasum -a 256 -c "swift-sourcery-templates-$VERSION.artifactbundle.zip.sha256"
unzip -q "swift-sourcery-templates-$VERSION.artifactbundle.zip"
```

A lane that only validates does not need the engine: `mock-templates-<version>-macos.zip` is
published beside the bundle, with its own `.sha256`.

The engine version a given checkout is checked against is recorded in the repository's
`Scripts/engine-pin.sh`. Building the CLI from source instead is `swift build --product
mock-templates` in a checkout of the templates package.

## `generate`

Runs the engine, then writes the output under its fingerprint.

| flag | meaning |
| --- | --- |
| `--sourcery <path>` | the generator executable to run |
| `--templates <path>` | the template file; its basename joins the recorded config line |
| `--sources <path>` | a root to scan — a directory or a single `.swift` file. Repeatable |
| `--args <key=value>` | a generator argument, passed through verbatim. Repeatable; sorted into the config line |
| `--bundle-version <tag>` | the template bundle tag, recorded on the bundle line |
| `--root <path>` | recorded input paths are relative to this directory. Default: the working directory |
| `--output <path>` | the file to write |
| `--disable-cache` | pass `--disableCache` to the generator |

At least one `--sources` root is required. A source outside `--root` is an error rather than an
absolute path in the block, so the recorded block reproduces across checkouts.

## `validate`

Re-hashes the recorded inputs and the body. The generator is not involved, so this runs on a cold
machine in seconds.

| flag | meaning |
| --- | --- |
| `--file <path>` | the generated file to check |
| `--root <path>` | recorded paths resolve relative to this directory |
| `--sources <path>` | a root the current config scans. Repeatable; enables the set check |
| `--expect-bundle <tag>` | fail unless the recorded bundle tag is exactly this |
| `--template <name or path>` | the template the current config generates with, recorded by basename. Enables the config check |
| `--args <key=value>` | a generator argument as the current config passes it. Repeatable; needs `--template` |

It fails on:

- a listed input whose content changed;
- a listed input that is gone;
- with `--sources`, a `.swift` file present under a root and absent from the block — the case where
  a file was added after generation and its types are missing from the output;
- a body whose hash differs from the recorded one, which is a hand-edit;
- with `--expect-bundle`, a block imprinted by a different bundle tag;
- with `--template`, a block whose config line names a different template or a different argument
  list from the one the caller passes.

`--args` without `--template` is refused: the config line names the template first.

Both config flags are optional. `validate` with neither still checks the inputs, the body and the
bundle tag. Pass them to cover the two generation inputs the hashes do not — the template that drove
the file and the arguments it was given.

## `imprint`

Rewrites the fingerprint block over an existing body without regenerating. It takes the same flags
as `generate` except `--sourcery` and `--disable-cache`, and reads `--output` as the file to
re-imprint. Use it when the recorded inputs moved but the generated body is known good — a source
file renamed, a `--root` changed.

## The script shape worth copying

One generation script in the repository, one output file per module, annotations for
externally-owned protocols in a directory of their own:

```bash
#!/bin/bash
set -euo pipefail

VERSION="<newest tag>"
BUNDLE=".build/swift-sourcery-templates-$VERSION.artifactbundle"   # downloaded and checksummed above
MOCK_TEMPLATES="$BUNDLE/mock-templates/bin/mock-templates"
TEMPLATES_DIR="${TEMPLATES_DIR:-$BUNDLE/templates}" # override for local template iteration

for module in Auth Firestore Storage; do
  "$MOCK_TEMPLATES" generate \
    --sourcery "$BUNDLE/sourcery/bin/sourcery" \
    --templates "$TEMPLATES_DIR/Mocks.swifttemplate" \
    --sources "Sources/$module" \
    --sources "SourceryAnnotations/$module" \
    --args "import=Foundation,testable=$module" \
    --bundle-version "$VERSION" \
    --root "$(pwd)" \
    --output "Tests/${module}Tests/Generated/${module}Mocks.swift"
done
```

The CI gate is the same loop with `validate` and `--file`, and it needs only the CLI zip.

`TEMPLATES_DIR` as an override matters when a template change is being tested: it points the run at
a working checkout of `templates/` while everything else stays pinned.

## Calling the generator directly

`mock-templates` is a wrapper. The engine can be run on its own when no fingerprint is wanted:

```bash
sourcery \
  --sources Sources/MyModule \
  --templates "$BUNDLE/templates/Mocks.swifttemplate" \
  --output Tests/MyModuleTests/Generated/MyModuleMocks.swift \
  --args "import=Foundation,testable=MyModule"
```

Repeat `--args` for additional imports. Without the fingerprint block there is nothing for CI to
validate against, so the committed file can go stale without any check noticing.

## What the fingerprint records

The block above the body names the template bundle tag, the config line (template basename plus the
sorted arguments), and the path and SHA-256 of every scanned source, all relative to `--root`, then
the SHA-256 of the body below it. Generation is deterministic, so a fingerprint that validates
implies the output is what the current sources and template produce.
