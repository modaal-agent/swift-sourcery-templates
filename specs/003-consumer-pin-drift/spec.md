# 003 — Two pins on one artifact, and a reference consumer five releases behind

**Status:** Proposed. Nothing here is decided and nothing is implemented. This document records what
was measured so the two questions can be picked up later; §3 and §4 list options without choosing
between them.

**Measurements:** every number, path and quoted string in §1 was produced on 2026-09-10 against
`master` at `227af72`, with 0.8.0 published, using the working copies of the other repositories
present on this machine under `/Volumes/DATA01/Projects/`. Nothing in any repository was changed to
take them, except `modaal-firebase-wrappers`, which was regenerated inside a throwaway `git worktree`
so its own checkout stayed clean (§1.4 records the method).

**Scope of the questions:** `Package.swift`, `Scripts/assemble-release.sh`, `CONTRIBUTING.md`'s
release procedure, and — outside this repository — `modaal-agent-duet-tools`'s manifest contract and
`modaal-firebase-wrappers`'s `scripts/generate-mocks.sh`. No template change is implied by either
question.

**Obsoletes:** 001 follow-up §20 question 1, which asked whether `duet`'s bundle pin and the
plugin's should become one pin and recorded the pair as unmeasured. §1.1–§1.3 measure it.

**Follows:** 001 follow-up §11.6 (who consumes the published assets), §14 (what the bundle carries),
and §18 step 3 (the commit that made the plugin resolve this repository's bundle, which is what
turned the question from hypothetical into a live condition).

---

## 0. TL;DR

1. Since 0.8.0, a repository that uses both the SPM plugin and `duet mocks` resolves the same
   artifact bundle twice, under two independent version numbers that nothing compares: the plugin's
   `binaryTarget` in the consumer's `Package.swift`, and `mocks: bundle:` in the consumer's
   `parity/manifest.yaml` (§1.3).
2. The two also fetch from different tags even at the same version number. The plugin's URL names the
   `templates-X.Y.Z` prerelease; `duet` builds its URL from the bare release tag (§1.1, §1.2).
3. `modaal-firebase-wrappers`, which `CONTRIBUTING.md`'s release procedure calls the reference
   consumer, is pinned at `0.2.15` and clones the pre-rename repository URL (§1.4).
4. Because of 3, step 2 of the release procedure measures the wrong delta: it produces a
   0.2.15→`master` diff, not the diff a consumer bumping from the previous release would see (§1.5).
   Measuring the release delta takes two generations and a diff between them, which is what was done
   for the 0.8.0 entry.

**Item 3, updated by §6.1:** `CONTRIBUTING.md` no longer calls any repository the reference consumer.

---

## 1. Measured

### 1.1 What the plugin pins

`Package.swift`'s `sourcery` binary target, at `227af72`:

```
url:      https://github.com/modaal-agent/swift-sourcery-templates/releases/download/
          templates-0.8.0/swift-sourcery-templates-0.8.0.artifactbundle.zip
checksum: b2dc387daba5ed9d56cf21d752e79522a8486f14b8beea34169130c634d09860
size:     22,672,047 bytes
```

The tag in that URL is `templates-0.8.0`, the prerelease published by the first of the two tags a
release cuts (001 follow-up §15). The `0.8.0` release published a bundle of the same name, built
from the same `templates/`, as a separate file with a different checksum. The pin names the
prerelease's copy, so deleting the `templates-0.8.0` prerelease breaks package resolution for every
consumer at 0.8.0 while every branch of this repository stays green. That is recorded here because
nothing in the repository states it except a PR body and a comment in `Package.swift`.

### 1.2 What `duet` pins

`modaal-agent-duet-tools/Sources/duet/Mocks.swift`:

- `:60` — `static let bundleRepo = "https://github.com/modaal-agent/swift-sourcery-templates"`.
- `:276` — `provision(repo:tag:check:)` caches into
  `<repo>/.build/swift-sourcery-templates-<tag>/swift-sourcery-templates-<tag>.artifactbundle`, and
  reads `mock-templates/bin/mock-templates` from it at `:286`.
- `:328-342` — `fetchVerified(asset:tag:into:)` builds
  `\(bundleRepo)/releases/download/\(tag)/\(name)` and fetches the asset and its `.sha256`. The tag
  is the bare release tag, so `bundle: 0.6.2` fetches
  `releases/download/0.6.2/swift-sourcery-templates-0.6.2.artifactbundle.zip` — the release's copy,
  not a `templates-` prerelease's.
- `:292-293` — under `--check`, a full bundle already cached by a regenerate run is reused; otherwise
  `mock-templates-<tag>-macos.zip` is fetched, which is why the standalone CLI asset stays published
  (001 follow-up F11).

`modaal-agent-duet-tools/contracts/manifest.md:114-118` documents the pin:

> `bundle:` — the release tag of the swift-sourcery-templates artifact bundle every row generates
> with. The bundle carries engine, templates and the `mock-templates` CLI together, so this one pin
> replaces an engine/templates version pair. Required once any generator row exists; bare semver.

`MOCK_TEMPLATES`, `SOURCERY` and `TEMPLATES_DIR` environment variables override the provisioned
paths (`:282-284`), so a caller can already point `duet` at a local checkout.

Every `parity/manifest.yaml` found on this machine pins `bundle: 0.6.2`: 13 trees under
`modaal-agent-duet-tutorials` (`tutorial3-complete` through `tutorial9-complete`), with 5 more
(`tutorial1-start`, `tutorial1-complete`, `tutorial2-start`, `tutorial2-complete`, `tutorial3-start`)
carrying no `bundle:` key at all. 001 follow-up §11.6 recorded nine tutorial trees on the same day;
the count here is 13, and the difference was not investigated. The two repositories §11.6 names as
running `duet mocks --check` in CI — `modaal-wikimemory-dgra0` and `modaal-onesec-py38p` — are not
checked out on this machine, so their pins were not re-read.

### 1.3 The two pins are independent, and nothing compares them

A repository that uses the SPM plugin and `duet mocks` now holds two pins on the same artifact:

| | pin | names | reads from the bundle |
| --- | --- | --- | --- |
| plugin | `Package.swift`'s `sourcery` binaryTarget | `templates-X.Y.Z` prerelease asset | `sourcery/bin/sourcery`, and `templates/` when neither the package graph nor `#filePath` yields one |
| `duet` | `mocks: bundle:` in `parity/manifest.yaml` | bare `X.Y.Z` release asset | `mock-templates/bin/mock-templates`, `sourcery/bin/sourcery`, `templates/` |

Nothing reads one pin while resolving the other, and no check compares them. With the values
measured above — plugin at 0.8.0, `duet` at 0.6.2 — one repository would generate through `duet
mocks` with 0.6.2's templates and through the build-tool plugin with 0.8.0's templates, and both sets
of generated code would sit in the same tree. Whether any repository is in that state was not
measured: no repository on this machine both uses the plugin and carries a `parity/manifest.yaml`.

Two mechanical facts bear on any fix. The plugin's pin needs a checksum, which is why it names a
specific published file rather than a tag; `duet`'s pin is a bare semver from which it derives asset
URLs at run time. And the artifact bundle's internal layout — `sourcery/bin/sourcery`,
`mock-templates/bin/mock-templates`, `templates/`, `info.json` at the root — is now depended on by
both `Scripts/assemble-release.sh` (which writes it), `duet` (which reads three paths out of it), and
`SourcerySwiftCodegenPlugin.swift`'s bundle route (which finds the root by looking for `info.json`).
`Tests/Checks/PluginFixtureBundleRoute` gates the plugin's half of that contract; nothing in this
repository gates `duet`'s half.

### 1.4 The reference consumer is five releases behind, on the pre-rename URL

`modaal-firebase-wrappers`, on `main`, clean, at `1f5cf93 "Re-pin mock templates to
swift-sourcery-templates 0.2.15"`. Its `scripts/generate-mocks.sh`:

- `:8` — `TEMPLATES_REPO="https://github.com/ivanmisuno/swift-sourcery-templates.git"`. That URL
  redirects to `modaal-agent/swift-sourcery-templates` — confirmed against the GitHub API, which
  resolved it to `full_name: modaal-agent/swift-sourcery-templates` — so the clone works.
- `:9` — `TEMPLATES_TAG="0.2.15"`, five releases behind 0.8.0.
- `:14` — `TEMPLATES_DIR` overrides the clone, which is how the measurement below was taken.
- `:20-24` — it requires `sourcery` on `PATH` and calls it directly. No `sourcery` is installed on
  this machine; the committed output's header reads
  `// Generated using Sourcery 2.3.0`, so the baseline was produced with the version this repository
  pins.
- `:86` — a comment reading "Templates 0.2.15 emit `final class`; earlier versions emitted `class`",
  which is the kind of statement that goes stale silently.

It uses neither published asset — no artifact bundle, no `mock-templates` CLI — which 001 follow-up
§11.6 already records.

**Method, so the measurement can be repeated.** A throwaway `git worktree` of the consumer at `main`,
`TEMPLATES_DIR` pointed at a templates tree, and this repository's pinned Sourcery 2.3.0 symlinked
onto `PATH`. The consumer's own checkout was never written to, and the worktree was removed
afterwards.

**Result.** 34 mocks across 7 modules — `ModaalFirebaseAuth` 7, `ModaalFirestore` 13,
`ModaalCloudStorage` 7, `ModaalFirebaseRemoteConfig` 4, and 1 each for `ModaalFirebaseAnalytics`,
`ModaalFirebaseCrashlytics` and `ModaalFirebaseMessaging`.

Regenerated against `master`, versus the committed output generated at 0.2.15:

```
 7 files changed, 218 insertions(+)
```

No deletions and no modifications. Every added line is the recorded-argument feature: one
`var <name>Args: [...] = []` per method and one `<name>Args.append(...)` inside it. Existing
`<name>CallCount` and `<name>Handler` members are untouched, so a test written against them keeps
compiling.

Regenerated against `master` versus against 0.7.0's `templates/`, extracted with
`git archive 0.7.0 templates`: **byte-identical in all seven files**. The only template change
between those two commits is a doc comment inside `templates/Mocks/MockMethod.swift`, which is
template source and is not emitted.

### 1.5 What step 2 of the release procedure actually measures

`CONTRIBUTING.md`'s "Cutting a release" step 2 says to regenerate the reference consumer against
`master` and record the size and shape of its diff, and `AGENTS.md` states the rule as "Do not tag
without measuring the consumer". Read literally against the consumer as it is pinned today, that
produces §1.4's 218-insertion diff, which spans 0.2.15→`master` — five releases — and answers a
different question from the one a consumer bumping one release asks.

For the 0.8.0 entry the release delta was measured instead, by generating twice (once from the
0.7.0 tag's `templates/`, once from the commit's) and diffing the two outputs. That is two
generations and a `diff -r` rather than one generation and a `git diff`, and nothing in
`CONTRIBUTING.md` says to do it.

**Updated by §6.1:** step 2 and the `AGENTS.md` rule quoted above no longer name a repository.

---

## 2. Not measured

- Whether any repository holds both pins at once. None on this machine does.
- Whether `modaal-wikimemory-dgra0` and `modaal-onesec-py38p` still pin `bundle: 0.6.2`; neither is
  checked out here.
- Why 001 follow-up §11.6 counted nine tutorial trees where §1.2 counts 13.
- Whether `duet` can read a consumer's `Package.swift` or `Package.resolved` at all — it is a Swift
  CLI operating on a repository, so it could, but nothing in `Mocks.swift` does today.
- Whether the two pins being independent is deliberate. `contracts/manifest.md:114-118` describes
  `bundle:` as replacing an engine/templates version pair; it does not mention the plugin.

---

## 3. Options for the two pins, none chosen

1. **Leave them independent and detect disagreement.** A check — in `duet`, or in a lane of the
   consumer's own — that reads the plugin's `binaryTarget` URL out of `Package.swift`, parses the
   version from it, and fails when it differs from `mocks: bundle:`. Costs one parser; does not
   change either pin's shape; needs a rule for repositories that hold only one pin.
2. **Make `duet` derive its pin from `Package.swift` when one is there.** `mocks: bundle:` becomes
   optional rather than required, and the manifest contract at `contracts/manifest.md:114-118`
   changes. Removes the pair entirely for repositories using both; the version then moves whenever
   the package graph resolves a new one, which is the opposite of what a pinned generator usually
   wants.
3. **Publish the plugin's pin as a value `duet` can read.** For example a small JSON file beside the
   release assets naming the tag and the bundle's SHA-256. Adds an asset; makes both consumers read
   one published fact rather than one reading the other's manifest.
4. **Do nothing, and document the pair.** Add the constraint to `README.md` where the plugin is set
   up and to `contracts/manifest.md` where `bundle:` is defined, so a reader of either learns the
   other exists.

Option 1 and option 4 are additive and reversible. Options 2 and 3 change a published contract, so
each needs `duet`'s own release cadence considered, which was not done here.

## 4. Options for the reference consumer, none chosen

1. **Bump `modaal-firebase-wrappers` to 0.8.0 and commit the regenerated output.** Makes the
   procedure's step 2 measure one release again from the next release onward. The bump itself is the
   218-line diff in §1.4, which is additive and needs no source change in that repository. It also
   wants `TEMPLATES_REPO` moved to the `modaal-agent` URL and the `:86` comment re-checked.
2. **Change what step 2 asks for.** State the two-generation method in `CONTRIBUTING.md` — generate
   at the pinned bundle's `templates/`, generate at the commit's, diff the two — so the recorded
   number is the release delta regardless of where the consumer is pinned. This is what was done for
   0.8.0 and it is not written down anywhere.
3. **Both.** They are independent: 1 fixes the consumer, 2 fixes the measurement.

Option 2 is the one that survives the consumer drifting again.

---

## 5. Open questions

1. **Is a consumer holding both pins a real configuration, or a hypothetical one?** §1.3. The answer
   decides whether §3 is worth building at all. Checking it means looking at the repositories not on
   this machine.
2. **Should the `templates-X.Y.Z` prereleases be protected from deletion?** §1.1. The plugin's pin
   names a prerelease asset, and deleting one breaks resolution for every consumer at that version
   with no signal on any branch. The weekly `published-example.yml` run detects it after the fact;
   nothing prevents it.
3. **Does anything gate the artifact bundle's layout on `duet`'s side?** §1.3. Three pieces of
   software now depend on the same layout, and only this repository's
   `Tests/Checks/PluginFixtureBundleRoute` asserts any of it.

---

## 6. Consumers taken out of the rules, CONTRIBUTING, CHANGELOG and CI, 2026-09-13

**Updates:** §0 item 3 and §1.5, which quote `CONTRIBUTING.md` naming the reference consumer. §4's options
stay open: the new step 2 does not say which delta to measure.

On 2026-09-13 the maintainer ruled that no adopting repository is named in `AGENTS.md`/`CLAUDE.md`,
`CONTRIBUTING.md`, `CHANGELOG.md` or the CI workflow; an analysis section in a spec is where one is named.
This section records what those files said before that day's edit.

### 6.1 `CONTRIBUTING.md`, `AGENTS.md`, `Tests/Checks/README.md` and `ci.yml`

| where | before | after |
| --- | --- | --- |
| `CONTRIBUTING.md`, after "The SPM plugin" | "`modaal-firebase-wrappers` uses the other mode: `sourcery` invoked from a script, output committed, so its consumers need no Sourcery installation." | "The other mode is `sourcery` invoked from a script with its output committed, so a repository consuming that output needs no Sourcery installation." |
| `CONTRIBUTING.md`, the pitfall on a refinement across modules | "the Duet reference app's `scripts/generate-mocks.sh` derives the set from `swift package dump-package` (every path dependency, plus the framework at its exact pin)" | "a generation script can derive the set from `swift package dump-package` (every path dependency, plus a framework at its exact pin)" |
| `CONTRIBUTING.md`, "Cutting a release" step 2 | "Regenerate the reference consumer (`modaal-firebase-wrappers`) against `master` and record the size and shape of its diff." | "Regenerate a consumer repository against `master` and record the size and shape of its diff." |
| `AGENTS.md`, "Do not tag without measuring the consumer" | "Its most-skipped step: regenerate `modaal-firebase-wrappers` against `master` and record the size and shape of its diff in the `CHANGELOG.md` entry." | "Its most-skipped step is the consumer regenerate: record the size and shape of the regenerated diff in the `CHANGELOG.md` entry." |
| `Tests/Checks/README.md`, "What the fixtures cover" | "mirror the Duet reference app" | "mirror one app's composition" |
| `.github/workflows/ci.yml`, the example-project lane | "teach test-ios.sh a `-derivedDataPath` and cache it, the way the modaal-firebase-wrappers workflow caches `.build/DerivedData`" | "teach test-ios.sh a `-derivedDataPath` under `.build/DerivedData` and cache that directory with `actions/cache`" |

`CONTRIBUTING.md`'s "Consumers" section, removed whole:

> - **[modaal-firebase-wrappers](https://github.com/modaal-agent/modaal-firebase-wrappers)** — the
>   reference consumer: 34 mocks across 7 modules, pre-generated and committed. Its
>   `scripts/generate-mocks.sh` is the adopter pattern worth copying — templates cloned at a pinned
>   tag, annotations in their own directory, one output file per module, `TEMPLATES_DIR` override for
>   local iteration. Regenerate it when measuring a release's consumer impact.
> - **The Duet reference app** — drove 0.2.15 and the Component template. 93 `/// sourcery:
>   CreateMock` annotations including an `<X>Dependency` protocol at each of its 13 composition
>   levels, built with `-strict-concurrency=complete`; the `Tests/Checks/Fixtures/` shapes are taken
>   from it. The shape the Component template emits is specified in `modaal-agent`'s
>   `specs/100-android-parity/27-duet-composition-shape.md` — §2 for the rule, §13 for the
>   macro-vs-template measurement behind choosing a template.

### 6.2 The repository behind each `CHANGELOG.md` measurement

| entry | it now reads | the repository | the analysis |
| --- | --- | --- | --- |
| 0.10.0, "A declaration generated inside `#if`" | a consumer repository | `modaal-firebase-wrappers` | 006 §13.2 |
| 0.9.0, "A mock member is the declared name plus a suffix" | a consumer repository; "12 sites in 5 files" | `modaal-firebase-wrappers`; the files are `FirebaseAuthCombineTests` (4), `DocumentReferenceCombineTests` (4), `QueryDocumentSnapshotProtocolTests` (2), `FirestoreCombineTests` (1) and `QueryCombineTests` (1) | 004 P9, §12.3, §13 |
| 0.9.0, "Annotation names are matched exactly" | both consumer repositories measured for this release | `modaal-firebase-wrappers` and the Duet reference app | 002, the cost paragraph above D13 |
| 0.8.0 | a consumer repository | `modaal-firebase-wrappers` | §1.4 |
| 0.6.2 | a consumer repository | `modaal-firebase-wrappers` | none |
| 0.5.0 | a consumer repository measured for this release | `modaal-firebase-wrappers` | none |
| 0.4.0 | a consumer repository; its mocks module | `modaal-firebase-wrappers`; `ModaalFirebaseMocks` | none |
| 0.3.1 | a consumer repository | `modaal-firebase-wrappers` | none |
| 0.3.0 | a consumer repository | `modaal-firebase-wrappers` | none |
| 0.2.15 | a consumer repository | `modaal-firebase-wrappers` | none |

### 6.3 Still named outside `specs/`

- `templates/Mocks/MockNaming.swift:111`, a comment: "47 of the 152 methods in the reference consumer". The
  `templates-0.10.0` bundle holds `templates/` with that comment, and `Scripts/check-pinned-templates.sh`
  refuses a release whose `templates/` differs from the pinned bundle's, so the comment changes after the
  `0.10.0` tag.
