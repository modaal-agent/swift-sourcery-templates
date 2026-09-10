# 002 — An annotation registry the templates read, rendered into every document, and an agent skill that teaches mock generation

**Status:** Written 2026-09-09, not implemented. **Two parts, and only the first one touches the
product.**

- **Part A — the registry (§2).** `templates/Annotations/` becomes the one place an annotation verb
  is named. Every template read routes through it, `Scripts/render-annotations.sh` renders it into
  each document that documents it, and `Tests/Checks/run-annotation-checks.sh` fails when a template
  reads a verb the registry does not declare, when the registry declares one no template reads, or
  when a rendered block is stale. Touches twelve files under `templates/` — two added, one deleted,
  nine edited — plus `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `Scripts/`, `Tests/Checks/` and
  `.github/workflows/ci.yml`.
- **Part B — the skill (§3–§6).** A `skills/` tree, two `.claude-plugin/` manifests, four install
  channels and a second check script. Touches no Swift and no template.

**Baseline:** `master` at `39a56d9`. **Obsoletes:** nothing. **Relates to:**
- [001](../001-plugin-source-discovery/spec.md) — §4.5 (bare template names), §4.6 (the keys the
  plugin fills in), §3.4 (the degraded Xcode path). The skill tells an adopter's agent to use those
  mechanisms; it does not restate why they exist.
- [AGENTS.md](../../AGENTS.md) §"State a rule once". Part A applies that rule to the annotation
  vocabulary, which is currently stated in eleven template files and again, by hand, in
  `README.md:609-631`.
- [CONTRIBUTING.md](../../CONTRIBUTING.md) §"A new annotation" (`:122-126`) — the procedure Part A
  replaces.

Every repository fact in §1 was read from this checkout on 2026-09-09. Every external fact in §3 and
§4 was read from the vendor documentation on the same date and is cited by page.

---

## 0. TL;DR

1. **`README.md:609-631` is a hand-maintained list, and it is already wrong.** The templates accept
   24 annotation spellings; the table documents 19. `annotatedGenericType`,
   `genericTypePlaceholder`, `genericTypesPlaceholder`, `associatedTypes` and `genericTypes` are
   accepted by `MockMethod.swift:231` and `Generics.swift:11-15` and appear in no document (§1.4).
2. **Five verbs match case-sensitively and fourteen do not, and nothing says so.** `CreateMock`,
   `TypeErase`, `DuetComponent`, `ObjcProtocol` and `owns` are read through a raw
   `annotations["…"]` subscript; every other verb goes through a case-insensitive path. So
   `/// sourcery: createmock` generates nothing, silently, while
   `/// sourcery: SKIPARGUMENTRECORDING` works (§1.5). Phase A4 makes every verb match exactly
   (§8, D3).
3. **The registry is `templates/Annotations/AnnotationRegistry.swift`** — one `static let` record per
   verb carrying `name`, `aliases`, `kind`, `target`, `effect` and `matching`. The three entry points
   `includeFile` it, so it is inlined into the same compilation unit the rest of the template
   already shares (§2.1). It is not loaded at runtime and there is no data file to locate.
   `kind` carries the schema `DuetComponent` already follows: **a selector is an UpperCamelCase noun
   naming what gets generated**, an option is lowerCamelCase, and check AC7 enforces it. So
   `CreateMock` becomes `ProtocolMock`, `TypeErase` becomes `TypeErasure`, and `ObjcProtocol` — today
   an option that means nothing without `CreateMock` beside it — is promoted to the selector
   `ObjcProtocolMock`. Every legacy spelling stays working as an alias, and after the move no name
   and no alias breaks the schema (§2.2, §8 D12).
4. **A template cannot be *prevented* from writing `annotations["Foo"]`** — that subscript is
   SourceryRuntime's own API and no Swift construct removes it. Check AC1 is a grep that fails when a
   string-literal annotation read appears outside `templates/Annotations/`. Calling it a lint rather
   than an impossibility is the honest description, and it is enforced on every push (§2.4).
5. **One scan answers misspellings, retirement and orphans.** Sourcery ignores an unrecognized
   annotation without a word, so a misspelling, a deleted verb and a typo all fail the same silent
   way. Because the registry knows every name, the templates can compare against it: a near-miss of
   a **selector** fails generation naming the canonical form, a near-miss of an **option** logs one
   line, a `retired` entry names its replacement, and check AC3 fails on a record no template reads
   (§2.5). The scan runs over *unfiltered* protocols, because a type whose selector is misspelled is
   not in the filtered list.
6. **One renderer, three documents, `--write` by hand, canonical names only.** `Scripts/render-annotations.sh`
   parses the registry with `awk` — no Swift toolchain — and writes between `<!-- annotations:start -->`
   and `<!-- annotations:end -->` in `README.md` and the two skill files. Aliases match but are
   documented nowhere: rendering one makes it a second canonical form with no way back (§8, D13).
   Check AC6 re-renders and compares, AC8 fails on an alias inside a block. This is
   `run-checks.sh --record`'s discipline applied to prose: run it, read the diff, commit it (§2.6).
7. **Phase A1 is a behaviour-preserving refactor; phase A4 is the narrowing.** The `matching:` field
   records today's split exactly, so phase A1's gate is an **empty** `run-checks.sh` diff and a
   reviewer reads it as pure mechanism. Phase A4 deletes the field, adds the scan, adds a red-control
   package whose `/// sourcery: protocolmock` must fail the build, and writes the `CHANGELOG.md`
   entry. A4 is required, not separable (§7, §8 D3).
8. **Part B is unchanged from the previous draft except that it gets simpler.** The skill's
   annotation table was going to be a hand-kept copy checked against README's; both are now
   renditions of the registry, and the check that compared two hand-kept copies is deleted (§6.1).
9. Four install channels over one `skills/` tree: `npx skills add`, the Claude Code plugin
   marketplace, manual copy, and the frontmatter restriction that keeps the skill uploadable to
   claude.ai (§4). **The skill stays in this repository**, because checks AC6, SC6 and SC7 all compare
   its text against a file here and a second repository would delay them (§8, D15). An Xcode project
   is sent to the CLI lane until 001 §11.2 closes the Xcode gap (§8, D14).

---

## 1. Current state (verified 2026-09-09)

### 1.1 What an adopter's agent has to read to set up generation today

Everything an adopter needs is in `README.md`, written for a person reading top to bottom:

| what the agent needs | where it is | size |
| --- | --- | --- |
| the `Package.swift` edit and the plugin's permission prompt | `README.md:262-318` | 1,833 B |
| a config per target, and the smallest one that works | `README.md:319-340` | 1,034 B |
| `${SOURCERY_SOURCES}` and the three ways a config says what to read | `README.md:341-369` | 1,453 B |
| bare template names and the four-step resolution order | `README.md:370-390` | 803 B |
| `output:` and its three outcomes | `README.md:391-400` | 491 B |
| the options the plugin leaves alone, and several templates in one config | `README.md:401-424` | 946 B |
| paths must be absolute | `README.md:425-431` | 423 B |
| the exported variables | `README.md:432-455` | 1,371 B |
| the degraded Xcode path | `README.md:456-477` | 1,056 B |
| the raw `sourcery` invocation | `README.md:478-497` | 553 B |
| `mock-templates generate` / `validate` / `imprint` | `README.md:498-548` | 2,839 B |
| the release artifact bundle | `README.md:549-579` | 1,608 B |
| the three template arguments | `README.md:580-591` | 438 B |
| the annotation reference — 19 rows | `README.md:609-631` | 1,697 B |

Those fourteen ranges are 16,545 bytes of the file's 32,542. An agent asked to "generate mocks for
this package" either reads all of it or greps and guesses.

**Amended 2026-09-10 — §11.2.** Every range above is as measured at the baseline `39a56d9`; 0.8.0's
README edits moved them. The row that changes in substance rather than position is the Xcode one: it
is now `README.md:475-497`, and it documents one degradation rather than a degraded path.

Two things the README does not say anywhere, because a person reading it already knows which
situation they are in:

- **Which lane to pick.** §"Swift Package Manager (SPM) prebuild plugin" and §"Standalone CLI
  (pre-generated mocks)" are presented as alternatives, and the parenthetical is the only statement
  of when the second one applies.
- **What a failure looks like before its cause is known.** CONTRIBUTING §Pitfalls records that a
  refining protocol across a module boundary surfaces as *"type 'XMock' does not conform to protocol
  'Y'"* in the consumer's build. CONTRIBUTING is addressed to someone editing the templates, and an
  adopter's agent has no reason to open it.

### 1.2 There is no skills tree and no plugin manifest

`ls -a` at the repository root on `39a56d9`: no `skills/`, no `.claude/`, no `.claude-plugin/`.

`.gitignore` ignores `.build`, `.swiftpm`, `/Packages`, `/Package.resolved` and the fixtures'
`Package.resolved`. It ignores neither `skills/` nor any dotted plugin directory, so both are
committed as written.

`Package.swift` declares targets under `Plugins/` and `Sources/` only. A top-level `skills/`
directory is outside every declared target path, so SwiftPM neither builds it nor warns about it.

### 1.3 How an annotation is read today

Fourteen template files, 2,162 lines in total. Four different spellings of "read an annotation":

| form | defined at | matching | sites |
| --- | --- | --- | --- |
| `annotations["X"] != nil` | SourceryRuntime's own `[String: NSObject]` | **exact** | `Mocks.swifttemplate:11`, `Component.swifttemplate:12`, `TypeErase.swifttemplate:27`, `MockGenerator.swift:98`, `ComponentGenerator.swift:110` |
| `annotations(for: ["x", …])` | `Utility/Annotations.swift:5-20` | case-insensitive | `_header.swifttemplate:11`, `MockMethod.swift:47`, `MockMethod.swift:231`, `SourceryRuntimeExtensions.swift:17`, `SourceryRuntimeExtensions.swift:75`, `ComponentGenerator.swift:97`, `ComponentGenerator.swift:116`, `Generics.swift:19` |
| `annotations[caseInsensitive: "x"]` | `Utility/Annotations.swift:58-62` | case-insensitive | `Annotations.swift:25`, `:34`, `:45`, `:54` |
| `annotations[caseInsensitiveKey: "x"]` | `SourceryRuntimeExtensions.swift:82-88` | case-insensitive | `SourceryRuntimeExtensions.swift:34` |

The third and fourth rows are the same five-line subscript, written twice under two labels:

```swift
// templates/Utility/Annotations.swift:58-62
private extension Dictionary where Key == String {
    subscript(caseInsensitive key: Key) -> Value? {
        return first { $0.0.lowercased() == key.lowercased() }?.value
    }
}
// templates/Mocks/SourceryRuntimeExtensions.swift:82-88 — identical body, different label
```

An `includeFile` inlines its file into one compilation unit, so both are visible at once and each is
`private` to keep them from colliding.

The include lines are explicit per entry point: `Mocks.swifttemplate:1-10` names ten,
`Component.swifttemplate:1-11` names eleven, and `TypeErase.swifttemplate:21-25` names five — only
`_header` and the four files under `Utility/`. A new file included by all three costs three lines.

### 1.4 The documented list is already behind the templates

`README.md:609-631` names 19 verbs. The templates accept 24 spellings. The five that appear in no
document:

| accepted spelling | read at | documented as |
| --- | --- | --- |
| `annotatedGenericType` | `MockMethod.swift:231` | — |
| `genericTypePlaceholder` | `MockMethod.swift:231` | — |
| `genericTypesPlaceholder` | `MockMethod.swift:231` | — |
| `associatedTypes` | `Generics.swift:11` | `associatedType` |
| `genericTypes` | `Generics.swift:14` | `genericType` |

`MockMethod.swift:231` reads all four of its names in one call:

```swift
if isGeneric, let extractedAnnotatedGenericTypesPlaceholder = $0.annotations(for: ["annotatedGenericType", "annotatedGenericTypes", "genericTypePlaceholder", "genericTypesPlaceholder"]).first {
```

No row of the table is stale in the other direction: all 19 documented verbs are read by some
template. The drift so far is entirely additions the table never received, which is the failure mode
the table's construction makes likely — a template author adds an alias inside an existing call and
the table has no row to change.

`excludedSwiftLintRules` is not an annotation. `_header.swifttemplate:2` reads it from
`argument[…]`, and `README.md:580-591` correctly lists it under template arguments.

### 1.5 The case-matching split is invisible

From the table in §1.3: `CreateMock`, `TypeErase`, `DuetComponent`, `ObjcProtocol` and `owns` match
the exact spelling. The other fourteen match any casing.

The consequence for an adopter: `/// sourcery: createmock` on a protocol produces no mock, no
warning and no error — Sourcery parses the annotation, stores it under a key no template asks for,
and generation completes. `/// sourcery: SKIPARGUMENTRECORDING` on a method works. Neither behaviour
is documented in `README.md` or `CONTRIBUTING.md`.

This is not a defect the registry has to fix, but it is one the registry has to *represent*: a table
generated from the templates has to say which of the two rules each verb follows, or the templates
have to stop having two rules (§2.1, §8 D3).

### 1.6 CONTRIBUTING's procedure for adding an annotation

`CONTRIBUTING.md:122-126`, §"A new annotation", is three numbered steps:

```
1. `Utility/Annotations.swift` — parsing
2. `Mocks/MockVar.swift` / `Mocks/MockMethod.swift`, or `Component/ComponentGenerator.swift`
3. Add the row to README.md's annotations table
```

Step 3 is the hand-maintenance §1.4 measured the result of. Part A replaces all three with: edit
`templates/Annotations/AnnotationRegistry.swift`, read the verb where the template needs it, run
`Scripts/render-annotations.sh --write`, commit what it wrote.

### 1.7 The CI change filter treats only `.md` as documentation

`.github/workflows/ci.yml:101`:

```bash
code_files="$(printf '%s\n' "$changed" | grep -vE '\.md$' || true)"
```

A push whose files all end in `.md` sets `code=false`, and the four macOS lanes — `checks:116`,
`cli:148`, `plugin:176`, `example-project:208`, each gated at `if: needs.changes.outputs.code ==
'true'` — do not run. The `rules` job (`:45-53`, `ubuntu-latest`, `cmp AGENTS.md CLAUDE.md`) is
deliberately not gated, because markdown is what it reads.

For the files these two parts add:

| file | matches `\.md$` | what CI does today |
| --- | --- | --- |
| `skills/swift-sourcery-mocks/SKILL.md` and `references/*.md` | yes | four macOS lanes skipped — correct |
| `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json` | no | four macOS lanes run: ~6 minutes and a simulator boot |
| `templates/Annotations/*.swift` | no | four macOS lanes run — correct, it changes generated output |
| `Scripts/render-annotations.sh`, `Tests/Checks/run-*-checks.sh` | no | four macOS lanes run — correct |

Row two is the defect §6.2 fixes. Rows three and four stay as they are.

A second consequence matters for Part A: a push that edits **only** `README.md` skips every macOS
lane, so the check that the rendered block is current has to run somewhere ungated. §2.6 puts it on
`ubuntu-latest` beside `rules`, and that is why the renderer parses the registry with `awk` instead
of compiling it (§8, D2).

---

## 2. Part A — the annotation registry

### 2.1 The file

`templates/Annotations/AnnotationRegistry.swift`. One record per verb, no imports beyond
`Foundation`, no reference to `SourceryRuntime` — so the file is readable by a text parser and
compiles inside the template's unit.

```swift
struct Annotation {
    let name: String          // the canonical spelling; the only one any document shows
    let aliases: [String]     // spellings that still match; documented nowhere (§2.5)
    let kind: Kind
    let target: String
    let effect: String
    let matching: Matching    // transitional — deleted by phase A4 (§8, D3)

    enum Kind { case templateSelector, option }
    enum Matching { case exact, caseInsensitive }
}

enum AnnotationRegistry {
    static let protocolMock = Annotation(
        name: "ProtocolMock",
        aliases: ["CreateMock", "Mock", "MockProtocol"],
        kind: .templateSelector,
        target: "Protocol / extension",
        effect: "Generate a mock class",
        matching: .exact
    )

    static let skipArgumentRecording = Annotation(
        name: "skipArgumentRecording",
        aliases: [],
        kind: .option,
        target: "Protocol / method",
        effect: "Do not generate `<method>Args`; call counting and the handler are unaffected",
        matching: .caseInsensitive
    )

    // … 17 more, one per row of the table README carries today

    static let all: [Annotation] = [createMock, skipArgumentRecording, /* … */]
    static let retired: [RetiredAnnotation] = []
}
```

**The record shape is the parser's contract.** Each record opens with a line matching
`^    static let [a-zA-Z]+ = Annotation\($`, carries exactly the six field lines in order, each
matching its own pattern, and closes with `^    \)$`. Check AC5 asserts that every line between an
opening and a closing line matches one of the six field patterns and that the number of
`Annotation(` occurrences equals the number of records parsed, so the parser cannot skip a record or
misread a field without failing.

`templates/Annotations/AnnotationAccess.swift` holds what `templates/Utility/Annotations.swift` holds
today — `annotations(for:)`, `isAnnotatedConst`, `isAnnotatedInit`, `isAnnotatedHandler`,
`isAnnotatedSkipArgumentRecording` — rewritten to take an `Annotation` rather than a string, plus the
**one** case-insensitive subscript that replaces both copies in §1.3.
`templates/Utility/Annotations.swift` is deleted, and the `includeFile` lines in the three entry
points are updated to name the two new files.

### 2.2 The naming schema the registry enforces

`kind` is not decoration. It carries a rule the existing vocabulary half-follows:

- **`.templateSelector` — an UpperCamelCase noun naming what gets generated.** It decides whether a
  template processes a type at all.
- **`.option` — lowerCamelCase.** It modifies how a selected type is generated.

`DuetComponent` already follows it: a noun naming the emitted class. `CreateMock` (verb plus noun)
and `TypeErase` (a verb) are the deviations, and `ObjcProtocol` is a third — UpperCamelCase, but it
adds an `NSObject` superclass to a mock `CreateMock` already selected (`MockGenerator.swift:96-101`),
which makes it an option wearing a selector's casing.

**The canonical names move, and every legacy spelling becomes an alias:**

| canonical (noun) | aliases that keep working | what it generates |
| --- | --- | --- |
| `ProtocolMock` | `CreateMock`, `Mock`, `MockProtocol` | a mock class |
| `ObjcProtocolMock` | `ObjcProtocol` | a mock class with an `NSObject` superclass |
| `TypeErasure` | `TypeErase` | a type-erasing wrapper |
| `DuetComponent` | — | the forwarding Component |

`ObjcProtocol` becomes a **selector** rather than an option, and that is what removes the exception
instead of relocating it. Today `ObjcProtocol` means nothing on its own: a protocol carrying it
without `CreateMock` is not in `Mocks.swifttemplate:11`'s filter and generates nothing. As a selector
it says the whole thing in one annotation, and the legacy pair still works — a protocol annotated
`CreateMock` *and* `ObjcProtocol` matches `ProtocolMock` through the first alias and
`ObjcProtocolMock` through the second, and generates exactly the mock it generates today.

After the move, **every name and every alias obeys the schema**: four UpperCamelCase selectors,
fifteen lowerCamelCase options, and the five undocumented spellings from §1.4 are lowerCamelCase
aliases of options. So check AC7 carries no exception clause — an earlier draft of this spec needed
one for `ObjcProtocol`, and the noun schema makes it unnecessary.

Two things the move does **not** cover:

- **`NSObjectProtocol` inheritance is a second, un-annotated trigger.**
  `MockGenerator.swift:96-101` reads `annotations["ObjcProtocol"] != nil || inheritedTypes.contains("NSObjectProtocol")`.
  The registry governs the annotation half; the inheritance half is derived from the type graph and
  stays where it is. `ObjcProtocolMock` is therefore sufficient but not necessary for an `NSObject`
  mock, and the rendered `effect` text has to say so.
- **`ObjcProtocol` has no test at all today.** It appears nowhere under `Tests/` — no fixture, no
  snapshot line, no example. Phase A4 adds the first coverage it has ever had (§7).

Check AC7 asserts, per record: `.templateSelector` names and aliases match `^[A-Z][A-Za-z]*$`,
`.option` names and aliases match `^[a-z][A-Za-z]*$`, every `.templateSelector` is read by at least
one entry point's filter, and every entry point's filter reads at least one `.templateSelector`. The
earlier draft's "exactly three selectors" is dropped: it was a count fitted to the vocabulary of the
day, and `ObjcProtocolMock` makes four without making anything wrong.

### 2.3 What the templates then look like

Each of the five raw subscripts in §1.3 becomes a registry read. `Mocks.swifttemplate:11`:

```swift
// before
<%= try MockGenerator.generate(for: types.protocols.map { $0 }.filter { $0.annotations["CreateMock"] != nil }) %>
// after
<%- try AnnotationRegistry.rejectNearMisses(in: types.protocols) -%>
<%= try MockGenerator.generate(for: types.protocols.map { $0 }.filter { $0.isAnnotated(any: AnnotationRegistry.mockSelectors) }) %>
```

`isAnnotated(_:)` applies the record's own `matching` rule, so `protocolMock`'s `.exact` keeps
`Mocks.swifttemplate` matching exactly what it matches today, through the `CreateMock` alias.

`AnnotationRegistry.mockSelectors` is `[protocolMock, objcProtocolMock]` — the one entry point whose
template has two selectors (§2.2). `MockGenerator.swift:96-101`'s `isObjcProtocol` then reads
`isAnnotated(AnnotationRegistry.objcProtocolMock) || inheritedTypes.contains("NSObjectProtocol")`.
**Both selectors on one protocol is not an error and needs no precedence rule**: the filter is a
union, `isObjcProtocol` is a separate question, and the pair `CreateMock` + `ObjcProtocol` that
consumers write today lands on exactly that path.

**`rejectNearMisses` runs before the filter, and that ordering is the whole point.** A protocol whose
`CreateMock` is misspelled is not in the filtered list, so a scan inside `MockGenerator.generate`
would never see it. Each of the three entry points gains one line over unfiltered `types.protocols`
(§2.5).

`MockMethod.swift:231`'s four names become one record with three aliases, and the call reads
`annotations(for: AnnotationRegistry.annotatedGenericTypes)` — the alias list moves from an argument
at the call site into the registry, where the renderer and the checks can see it.

`TypeErase.swifttemplate:27` takes the same treatment with `typeErasure`, whose `TypeErase` alias is
what `Tests/Examples/ExampleProjectSpm/Sources/ExampleProjectSpm/Protocols/Protocols.swift:122` and
every consumer's source still say.

### 2.4 What the registry cannot enforce, and what checks it instead

`annotations` is `[String: NSObject]` on SourceryRuntime's `Annotated` protocol. Nothing in Swift
removes a subscript from a type this repository does not own, so a template can always write
`annotations["Foo"]` and a new verb can always reach production without a registry entry.

**Check AC1 is a grep, and it runs on every push:**

```
grep -rnE 'annotations\[[^]]*"' templates/ --include='*.swift' --include='*.swifttemplate' \
  | grep -v '^templates/Annotations/'
```

Any hit fails the job, naming the file and line. The same run rejects
`annotations(for: ["literal"])` outside `templates/Annotations/`.

Stating this as a lint rather than as an impossibility matters for how the rule is written down:
`AGENTS.md` gets "an annotation verb is named once, in `templates/Annotations/AnnotationRegistry.swift`;
`Tests/Checks/run-annotation-checks.sh` fails on a string-literal annotation read anywhere else" —
a rule with a named home and a named check, not a claim that the code makes it impossible.

### 2.5 Misspellings, retirement, and orphans

Three ways a verb in a consumer's source can fail to mean what its author intended, and one
mechanism answers all three: the registry knows every name, so the templates can compare against it.

**A near-miss.** A key that equals a registry name or alias case-insensitively but not byte for byte
— `createmock`, `SkipArgumentRecording`, `ObjCProtocol`. Today this is silent: Sourcery stores the
annotation, no template asks for that key, generation completes, and the mock is simply absent.

The response depends on `kind`, because the damage and the false-positive risk both do:

| kind | response | why |
| --- | --- | --- |
| `.templateSelector` | `throw MockError.internalError(…)` naming the type, the spelling found and the canonical form — generation fails | The type generates *nothing*, which is the most damaging silent outcome, and the three selector names are distinctive enough that another template in the same run is unlikely to own a case variant. This is the idiom `ComponentGenerator.swift:239-244` already uses, under the rule `ComponentGenerator.swift:46` states: "a compile error, not a silent defect" |
| `.option` | one line on stderr naming the member, the spelling and the canonical form; generation continues | The type still generates; one option is missing. And an adopter running their own templates in the same Sourcery pass may legitimately own `Handler`, `Init`, `Import`, `Subject` or `Const`, so failing their build over a name this repository does not own would be wrong |

`print()` is not available for either: stdout is the generated file, which is how
`_header.swifttemplate:15` emits imports. §10.3 records that the stderr mechanism needs verifying
against Sourcery 2.3.0 before phase A4, and names two fallbacks.

**A retirement.** Deleting a shipped verb breaks consumers the same silent way: Sourcery accepts any
`/// sourcery: X`, and a template that stops asking produces no warning, so the adopter's next
regenerate quietly drops a mock, a `let`, an initializer entry or a Component.

```swift
    static let retired: [RetiredAnnotation] = [
        RetiredAnnotation(
            name: "genericTypePlaceholder",
            retiredIn: "0.8.0",
            replacement: "annotatedGenericTypes"
        ),
    ]
```

A retired name found in source produces the same response as a near-miss of the same `kind`, with the
replacement named. Three rules follow:

1. A verb that never appeared in a tagged release is deleted outright.
2. A verb that shipped is moved to `retired`, with the release that retired it and the replacement.
   It renders in no table.
3. A `retired` entry is deleted two minor releases after it was added. Check AC4 fails when a name
   appears in both lists.

**An orphan** is a record no template reads. Check AC3 greps `templates/` outside
`templates/Annotations/` for `AnnotationRegistry.<identifier>` and fails when the count is zero,
naming the record. It is cleared by deleting the record or retiring it, under the three rules above.

**The scan is deliberately narrow: near-misses of known verbs and retired names, nothing else.** A
key bearing no case-insensitive resemblance to any registry entry is another template's business and
draws no response.

**One corner widens rather than narrowing, and it is the only one.** A protocol annotated
`ObjcProtocol` *without* `CreateMock` generates nothing today (§2.2). Once `ObjcProtocol` is an alias
of the `ObjcProtocolMock` selector, it generates a mock — a new type in a consumer's build, arriving
from an annotation that was previously inert. Neither known consumer uses `ObjcProtocol` at all, and
neither does any fixture, so nothing measured here hits it; it is a `CHANGELOG.md` line for phase A4
regardless.

### 2.6 Rendering

`Scripts/render-annotations.sh` parses the registry with `awk` and writes one markdown table between
delimiters:

```markdown
<!-- annotations:start -->
| Annotation | Target | Effect |
|------------|--------|--------|
| `CreateMock` | Protocol / extension | Generate mock class |
…
<!-- annotations:end -->
```

**Canonical names only. No rendered document names an alias.** An alias exists so a spelling that
once worked keeps working; documenting one invites new code to use it, and then it is a second
canonical form with no way back. `README.md:609-631`'s nineteen rows are exactly the nineteen
canonical names, which is why the table stays the same size after phase A2 even though the registry
gains five aliases from §1.4.

Targets:

| file | block |
| --- | --- |
| `README.md` | §Annotations Reference, replacing `:609-631`'s hand-written table |
| `skills/swift-sourcery-mocks/SKILL.md` | the annotation section (§5.2) |
| `skills/swift-sourcery-mocks/references/writing-testable-protocols.md` | the same table, grouped by `kind` |

`--write` writes; with no flag the script re-renders into a temporary file and diffs, exiting
non-zero and printing the diff when a block is stale. A file with no delimiter pair is an error
naming the file, so a target cannot be silently dropped by an edit that removes the markers.

The renderer emits one sentence above the table stating how names are matched. While any record
carries `.caseInsensitive` — that is, between phases A1 and A4 — it instead emits a footnote naming
the records that match exactly. After phase A4 the `matching` field is gone and the sentence reads
"Annotation names are matched exactly, including case."

The `<!-- name:start -->` / `<!-- name:end -->` convention is the one `vercel-labs/skills`' README
uses for its generated agent list.

This is the discipline `AGENTS.md` already states for snapshots — run the gate, read the diff it
prints, then record — applied to prose. `run-checks.sh --record`'s wording and
`render-annotations.sh --write`'s wording are the same instruction about different artifacts.

### 2.7 The checks

`Tests/Checks/run-annotation-checks.sh`. `grep`, `awk` and `diff`; no Swift toolchain, no Sourcery,
no network. Runs on `ubuntu-latest` beside `rules`, ungated, in seconds.

| # | check | fails when |
| --- | --- | --- |
| AC1 | no string-literal annotation read outside `templates/Annotations/` | a template names a verb the registry does not declare (§2.4) |
| AC2 | every `static let … = Annotation(` record is listed in `AnnotationRegistry.all` | a record was declared and not listed, so the near-miss scan would not see it |
| AC3 | every record in `all` is referenced by name from a file outside `templates/Annotations/` | an orphan (§2.5) |
| AC4 | no name appears in both `all` and `retired`, counting aliases | a retired verb was re-added under its old name |
| AC5 | every line inside a record matches one of the six field patterns, and the count of `Annotation(` equals the count of parsed records | the parser would misread or skip a record |
| AC6 | `Scripts/render-annotations.sh` reports no stale block in any of the three targets | a rendition was not re-rendered after a registry edit, or a block was hand-edited |
| AC7 | names **and aliases** match `^[A-Z][A-Za-z]*$` for `.templateSelector` and `^[a-z][A-Za-z]*$` for `.option`; every selector is read by some entry point's filter; every entry point's filter reads some selector | the naming schema in §2.2 was broken, or a selector became unreachable |
| AC8 | no alias string appears inside any rendered block | an alias was documented (§2.6) |
| AC9 | every entry point calls `rejectNearMisses` over unfiltered `types.protocols` before its filter | a template would miss a misspelled selector (§2.3) |

AC1 and AC3 are the two directions of the user-visible rule: a verb the templates read is in the
registry, and a verb in the registry is read by the templates. AC6 and AC8 make every document's table
a build product rather than a copy.

A new `annotations` job in `.github/workflows/ci.yml`, `ubuntu-latest`, `needs:` nothing, `if:`
nothing — ungated for the reason §1.7 gives: a README-only push skips every macOS lane, and AC6 has
to run on exactly that push.

---

## 3. What an agent skill is

Read from the Claude Code documentation at `code.claude.com/docs/en/skills` on 2026-09-09.

### 3.1 The file, the frontmatter, the load path

A skill is a directory containing `SKILL.md`: YAML frontmatter between `---` markers, then markdown.
**The opening `---` must be the file's first line**; if it is not, the whole file is treated as skill
content and the frontmatter is never parsed.

```yaml
---
name: my-skill
description: What this skill does, and when to use it.
---

Instructions here.
```

Three load stages, and the budget each one spends:

1. **`description` — resident.** In context every turn, whether or not the skill is used, and the
   only thing the agent decides auto-invocation from. Capped at 1,536 characters (combined with
   `when_to_use`, where that field is used).
2. **The body — loaded on invocation, and it stays.** Once invoked, `SKILL.md` remains in context
   across turns, so every line is a recurring cost. The documented guidance is **under 500 lines**.
   Under auto-compaction the first 5,000 tokens of each skill survive, within a 25,000-token budget
   across all loaded skills.
3. **Linked files — loaded when the body sends the agent to them.** `[reference.md](reference.md)`
   costs nothing until the agent opens it. Scripts in the directory are executed, not read into
   context.

### 3.2 Where a skill is installed

Claude Code, in precedence order: the enterprise managed directory, then `~/.claude/skills/<name>/`
(personal, every project on that machine), then `.claude/skills/<name>/` (project, committed), then
nested `.claude/skills/` below the start directory, then `--add-dir` paths, then plugin skills at
`<plugin>/skills/<name>/`, invoked as `/<plugin-name>:<skill-name>`.

From the `skills` CLI's published table, for the four agents the install line names: Claude Code
`.claude/skills/` and `~/.claude/skills/`; Cursor `.agents/skills/` and `~/.cursor/skills/`; Codex
`.agents/skills/` and `~/.codex/skills/`; OpenCode `.agents/skills/` and
`~/.config/opencode/skills/`.

`synced` is reserved under `~/.claude/skills/` and must not be used as a skill name.

### 3.3 The frontmatter keys, and which ones survive an upload

Claude Code accepts 20 keys. Six are part of the Agent Skills standard — `name`, `description`,
`license`, `compatibility`, `metadata`, `allowed-tools`. The rest are Claude Code extensions:
`when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`,
`disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`, `paths`, `shell`.

Packaging for the Skills API or claude.ai rejects the extensions with a hard error naming the key:

```
Unexpected key(s) in SKILL.md frontmatter: argument-hint. Allowed properties are: allowed-tools, compatibility, description, license, metadata, name
```

`when_to_use` is an extension, so a skill that has to stay uploadable puts its trigger phrases in
`description` (§4.4, §8 D6).

### 3.4 What the documentation says about writing one

- Put the key use case first in `description`, and include trigger phrases and example requests.
- `SKILL.md` states what to do rather than narrating how or why; detail moves to linked files.
- Reference content — conventions, patterns, domain knowledge — stays auto-invocable. Task content
  with side effects (deploy, commit, send) sets `disable-model-invocation: true`.
- Testing is baseline comparison: the same realistic prompt in a fresh session with the skill and
  without it, compared side by side. A fresh session is required because context left over from
  authoring the skill hides gaps in what the skill actually says.

---

## 4. Distribution: four channels over one `skills/` tree

### 4.1 `npx skills add` — the cross-agent channel

The `skills` CLI (`github.com/vercel-labs/skills`, indexed at `skills.sh`) installs a repository's
skills into any of ~75 agents. It requires **no manifest and no registration**: it clones the source
and finds the skills in it. The Appllama repository named as the reference for this spec ships
exactly that — `skills/<name>/SKILL.md`, `skills/<name>/references/*.md`, and nothing else the CLI
needs.

```bash
npx skills add modaal-agent/swift-sourcery-templates
```

`ivanmisuno/swift-sourcery-templates` — the slug `README.md:3`'s CI badge and
`modaal-firebase-wrappers`' `scripts/generate-mocks.sh` both name — is a GitHub rename redirect to
`modaal-agent/swift-sourcery-templates` (`gh api repos/ivanmisuno/swift-sourcery-templates` returns
`"full_name": "modaal-agent/swift-sourcery-templates"`). Documented install lines name the canonical
slug so they do not depend on the redirect surviving.

Flags worth documenting, from the CLI's published option table: `-g/--global` installs to the user
directory instead of the project, `-a/--agent <agents...>` targets specific agents, `-s/--skill
<skills...>` selects skills by name, `-l/--list` lists without installing, `--copy` copies instead of
symlinking, `-y/--yes` skips prompts. `npx skills update` re-pulls installed skills.

### 4.2 The Claude Code plugin marketplace

`.claude-plugin/marketplace.json` at the repository root turns the repository into a marketplace.
Required keys: `name` (kebab-case), `owner.name`, `plugins`. Each plugin entry requires `name` and
`source`; `source` may be a path relative to the marketplace root.

`.claude-plugin/plugin.json` describes one plugin, and `name` is its only required key. With no
`skills` key the plugin loads skills from `skills/` **inside the plugin root**. The `skills` key adds
paths to that default rather than replacing it, every path must be relative and start with `./`, and
a path resolving outside the plugin root is rejected with `path escapes plugin directory`.

```
/plugin marketplace add modaal-agent/swift-sourcery-templates
/plugin install swift-sourcery-mocks@swift-sourcery-templates
```

### 4.3 Manual copy

```bash
git clone https://github.com/modaal-agent/swift-sourcery-templates
cp -r swift-sourcery-templates/skills/* ~/.claude/skills/     # or .claude/skills/ per project
```

### 4.4 The claude.ai / Skills API channel

Not a separate artifact: it is the frontmatter restriction in §3.3. Keeping `swift-sourcery-mocks` to
`name`, `description`, `license` and `metadata` means the same directory packages and uploads without
editing. It costs `when_to_use`, whose content moves into `description`, and forbids `paths`,
`allowed-tools` patterns and `disable-model-invocation`, none of which this skill needs (§8, D6).

### 4.5 One tree, and the arrangement that avoids a second copy

Channels 4.1, 4.3 and 4.4 read `skills/<name>/` at the repository root. Channel 4.2 reads `skills/`
**inside the plugin root** and cannot be pointed above it. So the plugin root has to be the
repository root:

```
.claude-plugin/
  marketplace.json     name: swift-sourcery-templates; plugins: [{ name: swift-sourcery-mocks, source: "./" }]
  plugin.json          name: swift-sourcery-mocks
skills/
  swift-sourcery-mocks/
    SKILL.md
    references/*.md
```

With `source: "./"` the plugin root is the marketplace root, its default `skills/` is the tree the
other three channels read, and no file is duplicated.

**This is the one arrangement in this spec that is not verified.** The documentation states that `.`
and `./` denote the plugin root and that a marketplace may hold plugins in subdirectories; it does
not show a plugin whose source is the marketplace root itself, and
`anthropics/claude-plugins-official` uses subdirectories throughout
(`plugins/<name>/.claude-plugin/plugin.json`, with `git-subdir` sources for third parties). Phase B1
verifies it against a local checkout. If it is rejected, the fallback is the subdirectory shape with
a second copy of the tree, kept in step by a `diff -r` in `run-skill-checks.sh` (§8, D9).

---

## 5. What the skill teaches

### 5.1 The lane decision, which is the first thing in the body

| the repository in front of the agent | lane |
| --- | --- |
| a SwiftPM package whose mocks are compiled into a test target of that same package | SPM build-tool plugin |
| an Xcode project with no `Package.swift` | **the CLI lane.** The plugin runs there, but `${SOURCERY_SOURCES}` cannot derive a closure and bare template names do not resolve (`README.md:456-477`), so a protocol refining one from another module generates an incomplete mock with no diagnostic — §8, D14 |
| mocks committed to the repository, so a consumer or a cold CI job runs no Sourcery | `mock-templates generate`, with `mock-templates validate` as the CI gate |
| a library that ships mocks as a product to downstream packages | `mock-templates generate`, committed; generated mocks are `internal`, so the consumer writes `@testable import` (CONTRIBUTING §Open items) |

**Amended 2026-09-10 — §11.2.** Row 2 is superseded. At 0.8.0 a bare template name resolves in an
Xcode project and `SOURCERY_TEMPLATES` is exported there, so the row's lane becomes the plugin. What
remains of the degradation is `${SOURCERY_SOURCES}`, which reaches the target's own input-file
directories and no further; the author names every other directory in `sources:` as an absolute path
built from `${SOURCERY_PROJECT}`. §11.2 carries the four differences the skill has to teach.

### 5.2 `SKILL.md` — the resident part

```yaml
---
name: swift-sourcery-mocks
description: <one paragraph, <=1024 characters>
license: Apache-2.0
metadata:
  repository: https://github.com/modaal-agent/swift-sourcery-templates
---
```

`license: Apache-2.0` matches `LICENSE.txt`. The `description` budget is 1,024 characters against the
1,536 cap, leaving headroom for a `when_to_use` if the claude.ai constraint is ever dropped. It names
the two lanes and carries trigger phrases: generate mocks for a Swift protocol, set up Sourcery,
protocol mock, test double, `ProtocolMock`, `CreateMock`, type erasure, `DuetComponent`, and the
`"does not conform to protocol"` symptom. The legacy spellings appear in the description — where a
user's words are matched, not where the vocabulary is documented — because an adopter's existing
source and their question will both say `CreateMock` for as long as D13's retirement is unscheduled.

Body, budgeted at **under 400 lines** against the documented 500:

| section | what it holds | budget |
| --- | --- | --- |
| the lane decision | the table in §5.1 | ~20 lines |
| annotating | `/// sourcery: CreateMock`, the external-protocol extension pattern, and the rendered annotation table between `<!-- annotations:start -->` and `<!-- annotations:end -->` | ~45 lines |
| the plugin lane, minimal path | the `Package.swift` edit, the three-line config, `${SOURCERY_SOURCES}`, `output:`, bare template names | ~70 lines |
| the CLI lane, minimal path | `mock-templates generate` and `validate`, and where the binaries come from | ~60 lines |
| what the generated mock gives a test | call counts, `<name>Handler`, `<name>Args`, smart defaults | ~50 lines |
| failure modes | the table in §5.4 | ~45 lines |
| links to `references/` | one line each | ~10 lines |

### 5.3 `references/` — loaded per lane

| file | what it holds | budget |
| --- | --- | --- |
| `references/spm-plugin.md` | the full config reference: the three ways a config says what to read, the exported variable table, the four-step template-name resolution, `args.testable`, several templates in one config, the Xcode degradation | ≤250 lines |
| `references/cli-lane.md` | every `mock-templates` flag, what `validate` fails on, `imprint`, the artifact-bundle download and checksum, and the `generate-mocks.sh` shape from `modaal-firebase-wrappers` | ≤250 lines |
| `references/writing-testable-protocols.md` | what to annotate and how to shape a protocol so its mock is usable, plus the rendered table grouped by `kind` | ≤200 lines |
| `references/troubleshooting.md` | the long form of §5.4, one section per symptom | ≤200 lines |

### 5.4 The failure modes the body names

Sources: CONTRIBUTING §Pitfalls, CONTRIBUTING §"Design rules already decided", `README.md:308-316`,
`README.md:391-400`.

| symptom | cause | action |
| --- | --- | --- |
| `type 'XMock' does not conform to protocol 'Y'` | the refined protocol was not among the parsed sources | plugin: put `- ${SOURCERY_SOURCES}` in `sources:`; CLI: add the other module's directory to `--sources` |
| the target compiles, and a generated type is missing | `output:` named a directory the build does not collect from | omit `output:`, or write `${SOURCERY_OUTPUT_DIR}`; any other value fails the build naming both paths |
| `sourcery` will not run — unidentified developer | the artifact-bundle binary is quarantined | `xattr -dr com.apple.quarantine <DerivedData>/SourcePackages/checkouts/swift-sourcery-templates/Plugins/Sourcery/sourcery.artifactbundle/sourcery/bin/sourcery` |
| a protocol from another package generates no mock | its source carries no annotation, and it is not yours to edit | annotate an empty extension in a `SourceryAnnotations/` directory and add that directory to the sources |
| generation fails: `'createmock' on 'Foo' is not 'CreateMock'` | a selector was misspelled; after phase A4 that is an error rather than silence (§2.5) | spell it `CreateMock` — names are matched exactly, including case |
| a Combine test hangs, or a continuation resumes twice | an `AnyPublisher` member is backed by a `PassthroughSubject` and does not replay | send after subscribe, return a `CurrentValueSubject` from `<name>GetHandler`, or annotate `subject = "CurrentValue"` |
| `<method>Args` does not exist | the method's parameters are all closures, or it is generic, or `skipArgumentRecording` is on it or its protocol | assert through `<name>Handler` |
| a Component emits a diagnostic naming a member | `static`, `init` and `subscript` requirements and associated types are not forwardable | hand-write that member, or use `owns` and a hand-written subclass |
| Swift 6 rejects the test body | a mock of a non-isolated protocol is a non-Sendable class; building it on the main actor and calling a nonisolated `async` member crosses an isolation boundary | make the test body non-isolated |
| subclassing a mock does not compile | mock classes are `final` | set a handler |

### 5.5 What the skill must not contain

`AGENTS.md` §"State a rule once" applies to the skill as it applies to a call site:

1. **A rule is stated in the templates and documented in README; the skill says what to do and does
   not re-derive why.** "Write `- ${SOURCERY_SOURCES}` in `sources:`" belongs in the skill. The
   measurement showing that Sourcery discards command-line `--sources` when `--config` is present
   belongs in 001 §1.4/A, where it already is.
2. **The annotation table is not written by hand at all.** It is rendered from
   `templates/Annotations/AnnotationRegistry.swift` into the skill's delimited block, the same way it
   is rendered into README's (§2.5). The previous draft of this spec kept a hand-written copy in the
   skill and compared it with README's; Part A removes both copies.
3. **No contributor material.** How the templates are built, `run-checks.sh --record`, the snapshot
   diff, the release procedure: CONTRIBUTING and AGENTS.md, not the skill (§9).

---

## 6. Part B's gate

### 6.1 `Tests/Checks/run-skill-checks.sh`

Reads markdown and JSON. No Swift toolchain, no Sourcery, no network — so it runs on
`ubuntu-latest` beside `rules` and `annotations`, in seconds.

| # | check | fails when |
| --- | --- | --- |
| SC1 | frontmatter opens at line 1 and parses | the file starts with anything but `---` |
| SC2 | `name:` equals the containing directory name, and is not `synced` | they differ |
| SC3 | frontmatter keys ⊆ {`name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`} | a Claude Code extension key is present (§4.4) |
| SC4 | `description` is 1–1,024 characters | empty, or over budget |
| SC5 | `SKILL.md` ≤ 400 lines; each `references/*.md` ≤ 250 | over budget |
| SC6 | every `SOURCERY_*` name the skill writes appears in `Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift` | the skill names a variable the plugin does not export |
| SC7 | every `mock-templates` long flag the skill writes appears in `Sources/mock-templates/Commands.swift` | the skill names a flag the CLI does not declare |
| SC8 | every relative link in the skill tree resolves to a file that exists | a moved or misspelled reference file |
| SC9 | no semver literal (`[0-9]+\.[0-9]+\.[0-9]+`) anywhere in the skill tree | a version was pinned in a snippet (§8, D7) |
| SC10 | both `.claude-plugin/*.json` files parse, and the marketplace entry's `name` equals `plugin.json`'s `name` | a manifest was edited on one side only |
| SC11 | the marketplace entry's `source` resolves to a directory containing `skills/<name>/SKILL.md` | the plugin root and the skill tree came apart |

The annotation table inside the skill is check AC6's, not this script's.

SC6 and SC7 extract two sets of names with `grep -o` and compare them, so rewording a sentence on
either side leaves them green.

### 6.2 The CI jobs, and the change filter

Three edits to `.github/workflows/ci.yml`:

1. **An `annotations` job** (§2.6), `ubuntu-latest`, ungated: `Tests/Checks/run-annotation-checks.sh`.
2. **A `skills` job**, `ubuntu-latest`, ungated for the same reason `rules` is:
   `Tests/Checks/run-skill-checks.sh`.
3. **The change filter at `:101`** grows the two paths that cannot reach a Swift build:

   ```bash
   code_files="$(printf '%s\n' "$changed" | grep -vE '\.md$|^\.claude-plugin/|^skills/' || true)"
   ```

   A push touching only `skills/` and `.claude-plugin/` then skips `checks`, `cli`, `plugin` and
   `example-project` — about six minutes and a simulator boot — and still runs `rules`, `annotations`
   and `skills`. `templates/Annotations/` is deliberately **not** in the pattern: it changes what the
   templates emit, so it runs every lane.

The filter keeps its fail-open property: the added alternatives only ever move a file out of
`code_files`, and the two early `code=true` returns at `:89` and `:95` are untouched.

---

## 7. Phasing

Part A lands first: the skill's annotation block is one of the renderer's targets, so phase B1 cannot be
written until `Scripts/render-annotations.sh` exists. Each phase is one reviewable commit.

| phase | what lands | gate |
| --- | --- | --- |
| A1 | `templates/Annotations/AnnotationRegistry.swift` and `AnnotationAccess.swift`; `Utility/Annotations.swift` deleted; every verb routed through the registry; the canonical moves of §2.2 (`ProtocolMock`, `ObjcProtocolMock`, `TypeErasure`) with every legacy spelling and §1.4's five kept as aliases; `Mocks.swifttemplate`'s filter widened to the two mock selectors; the duplicate case-insensitive subscript collapsed; three `includeFile` lists updated | `Tests/Checks/run-checks.sh` with an **empty** snapshot diff. The fixtures say `CreateMock` 22 times and nothing anywhere says `ObjcProtocol`, so an empty diff is exactly what proves the alias path equivalent. A non-empty diff means the commit changed behaviour and is wrong |
| A2 | `Scripts/render-annotations.sh`; the delimited block in `README.md`; `CONTRIBUTING.md:122-126` rewritten | `Scripts/render-annotations.sh` clean; the README diff read by hand — it reorders and rewords rows, and gains the five spellings §1.4 measured |
| A3 | `Tests/Checks/run-annotation-checks.sh` (AC1–AC9); the `annotations` job | each of AC1–AC9 red against a seeded violation, then green; a `README.md`-only push running `annotations` and skipping the four macOS lanes, read from the run's own log |
| A4 | `matching:` deleted, every verb matched exactly; `rejectNearMisses` in the three entry points; the stderr path for options (§10.3); fixtures for the canonical spellings and for a standalone `ObjcProtocolMock` — the first coverage `ObjcProtocol` has ever had (§2.2); the `CHANGELOG.md` entry naming the narrowing, the diagnostic and the `ObjcProtocol` widening | `run-checks.sh` diff containing exactly the new fixtures' mocks and nothing else, then `--record`. A new red-control package under `Tests/Checks/PluginFixtureRed/` whose protocol is annotated `/// sourcery: protocolmock` and whose build must fail, naming the type and `ProtocolMock`. A CLI-lane assertion that a misspelled **option** logs one line and still generates |
| A5 | *taken, in a release after this spec's others (§10.4).* `CreateMock`, `TypeErase` and `ObjcProtocol` moved from `aliases` to `retired`; both reference consumers re-annotated and regenerated in that release | the retirement path red against an un-renamed source; the consumer diffs recorded in `CHANGELOG.md`, which CONTRIBUTING §"Cutting a release" already requires (§8, D13) |
| B1 | `skills/swift-sourcery-mocks/SKILL.md` and the four `references/*.md`, with rendered annotation blocks; `.claude-plugin/marketplace.json` and `plugin.json` | `/plugin marketplace add ./` on a local checkout, then `/plugin install`; `npx skills add ./ --list`. §4.5's `source: "./"` is answered here; on rejection, take D9's fallback |
| B2 | `Tests/Checks/run-skill-checks.sh`; the `skills` job and the filter edit | the script red on a seeded violation of B2, B3, B5, B9 and B10, then green |
| B3 | `README.md` §"Agent skill" with the four install channels; `CONTRIBUTING.md` layout, testing and CI entries; the `AGENTS.md` rules from §2.3 and §5.5, then `cp AGENTS.md CLAUDE.md` | both check scripts; `cmp AGENTS.md CLAUDE.md` |
| B4 | *separable.* `skills/swift-sourcery-mocks/evals/evals.json` | the baseline comparison in §7.1 |

**A4 is required, not separable** (§8, D3): until it lands the registry carries `matching:` and the
rendered tables carry a footnote naming the five exact-match verbs, so the vocabulary is documented as
irregular because it is. Phase B4 may be dropped without affecting the rest.

A4 is the only phase that changes what an existing consumer's sources generate, and it narrows: a
verb that matched any casing now matches one. That is why it ships with the near-miss scan in the
same commit — the scan is what turns the narrowing from silence into a message.

**Amended 2026-09-10 — §11.1, §11.3.** A1–A4 have landed, one commit each, every push green;
§11.1 names the commits and the runs. Two rows read differently now. A4's gate was written before
§10.3 was measured, and the mechanism it chose is the comment line, not the stderr path (§11.5).
B2's "filter edit" is no edit: `run-skill-checks.sh` reads markdown, so its job belongs outside the
`changes` filter beside `annotations` and `rules`, which is where an ungated job already sits
(§11.3).

### 7.1 The baseline comparison

Per §3.4: each prompt run twice in a fresh session, once with the skill installed and once with it
disabled through `skillOverrides`, and the two transcripts compared. Five prompts, three with a
single correct lane and two with a single correct diagnosis:

1. "Add mock generation to this package" — against a SwiftPM package with a test target. Correct: the
   plugin lane, a `Package.swift` plugin entry, a `templates: [Mocks]` config beside the test target,
   no `output:`.
2. "Generate mocks and commit them so consumers don't need Sourcery" — correct: the CLI lane,
   `mock-templates generate`, and a `validate` step in CI.
3. "Mock this protocol from another module" — correct: `${SOURCERY_SOURCES}` on the plugin lane, an
   added `--sources` on the CLI lane.
4. "The build says `PaymentsMock does not conform to protocol Refunding`" — correct: the refined
   protocol is not among the parsed sources, and the lane-specific fix.
5. "This test hangs waiting on the mock's publisher" — correct: `AnyPublisher` is backed by a
   `PassthroughSubject`; send after subscribe, supply a `CurrentValueSubject` through the get
   handler, or annotate `subject = "CurrentValue"`.

A prompt whose with-skill run is wrong is a defect in the skill's text: edit the skill, then re-run
that prompt in a fresh session.

---

## 8. Decisions

**D1 — The registry is a Swift file the templates `includeFile`, not a data file they load.**
`includeFile` inlines its target into the template's single compilation unit, which is how
`Component/ComponentGenerator.swift` already reaches `private` declarations in
`Mocks/MockMethod.swift`. A JSON or YAML registry would have to be found at generation time from a
path that differs between the plugin lane, the CLI lane and the check lanes, and a missing file would
degrade to an empty vocabulary rather than to a compile error.

**D2 — The renderer parses the registry with `awk`, and does not compile it.** §1.7: a push that
edits only `README.md` skips every macOS lane, so check AC6 has to run on `ubuntu-latest`, which
carries no Swift toolchain. The cost is the strict record format and check AC5, which exists only to
make the text parse total. The rejected alternative — a `swiftc` two-file compile of the registry
plus a renderer — type-checks the registry but puts check AC6 behind a toolchain, where the push that most
needs it never reaches.

**D3 — Every verb matches exactly, and the narrowing ships with the scan that reports it.** §1.5
measured two rules in use; one has to win. Exact matching wins because it is what makes the naming
schema in §2.2 mean anything: if `createmock`, `CreateMock` and `CREATEMOCK` are one verb, then
"selectors are UpperCamelCase" describes nothing a consumer can rely on, and the registry cannot
enforce a convention the matcher ignores.

It is a **narrowing** — fourteen verbs currently accept any casing and will accept one — so it cannot
be shipped silently. The near-miss scan in §2.5 is what makes it legible: every spelling that stops
working produces either a failed generation naming the canonical form, or a log line naming it. The
aliases in the registry carry the case variants known to have shipped; the scan covers the rest.

Phasing follows from that. A1 keeps `matching:` and changes no behaviour, so its gate is an empty
snapshot diff and a reviewer can read it as a pure refactor. A4 deletes the field, adds the scan and
writes the `CHANGELOG.md` entry. Two commits, two gates, and the semantic change is not hidden inside
the mechanical one.

**Rejected: unify to case-insensitive.** It is a widening, so it breaks nobody, and an earlier draft
of this spec recommended it for that reason. It also permanently gives up the schema of §2.2: if every casing of a
name is the same verb, `ProtocolMock` and `CreateMock` can never be more than two ways to say one
thing, the retirement in D13 can never be made to bite, and a reader has no way to tell which
spelling is the one to write.

**D4 — The scan fires on near-misses and retired names, never on unrecognized ones, and its severity
follows `kind`.** §2.5. A key bearing no resemblance to any registry entry belongs to another
template in the same Sourcery run and draws no response. Among the keys that do resemble one, a
misspelled **selector** produces nothing at all, so it fails generation; a misspelled **option**
leaves a working mock missing one behaviour, and an adopter may legitimately own `Handler`, `Init`,
`Import`, `Subject` or `Const` for their own template, so it logs instead. Retirement is deletion
with a message: without the `retired` list, removing a shipped verb turns every consumer's
`/// sourcery: X` into a silent no-op on their next regenerate.

**D5 — One skill, not one per lane.** The first thing the agent does is choose a lane (§5.1), and
with two skills that choice is made by whichever `description` matched, before either body is loaded.
Cost of the single skill: an adopter on the plugin lane carries the ~60 lines of CLI material in
context for the rest of the session. Cost of the split: an agent that loads `swift-sourcery-cli` for
a package whose mocks only ever compile into its own test target, and commits generated files the
plugin would have produced at build time.

**D6 — Frontmatter restricted to the Agent Skills standard keys.** The cost is `when_to_use`, whose
content moves into `description` under the same 1,536-character cap. What it buys is that the same
directory packages for the Skills API and uploads to claude.ai unedited (§4.4). Check SC3 enforces it.

**D7 — No version literal anywhere in the skill tree.** A `from: "0.7.0"` in a `Package.swift`
snippet is wrong the day after the next tag, and no check in the adopter's repository reads it. The
skill's snippets carry a placeholder and the instruction to resolve the newest tag. Rejected
alternative: allow literals and gate them against `git tag --sort=-v:refname | head -1`, which needs
tags on the runner and re-breaks CI at every release. Check SC9 enforces this.

**D8 — The skill teaches adopters, not contributors.** Its audience is an agent working in a
repository that *uses* these templates. Editing the templates is CONTRIBUTING's and AGENTS.md's
subject, and both are already loaded by an agent working in this repository.

**D9 — `source: "./"`, with a named fallback.** §4.5's arrangement keeps one tree across all four
channels and is verified in phase B1. If the plugin loader rejects a plugin rooted at the marketplace
root, the fallback is `plugins/claude/` holding `.claude-plugin/plugin.json` and a second copy of
`skills/`, with `diff -r skills plugins/claude/skills` added to `run-skill-checks.sh` as SC12. The
fallback is written down here so the decision is not re-opened during implementation.

**D10 — Two check scripts, not one.** `run-annotation-checks.sh` gates the product's vocabulary and
survives Part B being dropped; `run-skill-checks.sh` gates the skill. Both are shell, both run on
`ubuntu-latest`, and both sit under `Tests/Checks/` beside the three existing lanes.
`Scripts/render-annotations.sh` sits under `Scripts/` with `assemble-release.sh`, because it is a
thing a person runs to produce a committed artifact rather than a gate.

**D11 — `skills/` at the repository root, not under `Tests/` or `docs/`.** The `skills` CLI and the
plugin loader both look there; moving it costs a `skills` key in `plugin.json` and makes channel 4.1
depend on a path the CLI is not documented to search.

---

**D12 — A selector is an UpperCamelCase noun naming what gets generated; the canonical names move to
match.** §2.2. `DuetComponent` already followed the rule. `CreateMock` (verb plus noun), `TypeErase`
(a verb) and `ObjcProtocol` (an option in a selector's casing) did not, and become `ProtocolMock`,
`TypeErasure` and `ObjcProtocolMock`, with every legacy spelling kept as an alias.

**Promoting `ObjcProtocol` to a selector is what makes the schema exception-free.** An earlier draft
demoted it to an option named `objcProtocol`. That satisfied the casing rule while keeping the shape
that made it odd — an annotation meaning nothing unless a second one is present. As a selector it
says the whole thing at once, and after the move no name and no alias in the registry breaks the
rule, which is why check AC7 needs no exception clause.

Cost: the documented name and the name in every existing codebase differ until D13's retirement
lands. `CreateMock` appears 22 times across `Tests/Checks/Fixtures/`, 93 times in the Duet reference
app, and behind 34 mocks in `modaal-firebase-wrappers` (CONTRIBUTING §Consumers). That is why the
rename is only worth making if it is finished — D13.

**D13 — Aliases match, are documented nowhere, and the three legacy selectors are retired in a later
release.** An alias exists because a spelling shipped, or because a hand-written annotation was
plausibly mistyped from memory. Rendering one would make it a second canonical form with no way back
and would double the table for no reader's benefit; check AC8 fails when an alias string appears
inside a rendered block. §1.4's five undocumented spellings become aliases in phase A1 and stay.

`CreateMock`, `TypeErase` and `ObjcProtocol` are handled differently from those five. Left as
permanent aliases, `README.md` and the skill would say `ProtocolMock` while every real codebase says
`CreateMock`, and an adopter who greps the documented name finds nothing — worse than never renaming.
So phase A5 moves the three to `retired` in a release after this one, where §2.5's retirement path
turns an un-renamed source into a failed generation naming the replacement instead of a silent no-op.
The migration is one `sed` per repository, and both reference consumers are regenerated in that
release anyway, which CONTRIBUTING §"Cutting a release" already requires.

**A5 is taken.** The release it lands in is open (§10.4); whether it lands is not. That order matters
because D12 depends on it: an unfinished rename — the table saying `ProtocolMock` while every
codebase says `CreateMock`, indefinitely — costs more than the irregular vocabulary it fixes. A
future decision to drop A5 is a decision to revert D12 with it.

**D14 — The skill directs Xcode projects to the CLI lane until 001 §11.2 is closed.** The plugin runs
under `XcodeBuildToolPlugin`, but with no package graph `${SOURCERY_SOURCES}` cannot derive a closure
and `SOURCERY_TEMPLATES` is not exported (`README.md:456-477`). The failure that produces is the one
§5.4's first row describes — an incomplete mock, surfacing as a conformance error in the consumer's
build — and it arrives with no diagnostic. A skill that walked an agent into it would be worse than
one that does not mention the plugin for Xcode at all. So: the lane table sends Xcode projects to the
CLI lane, and `references/spm-plugin.md` carries one paragraph naming the two degradations and
pointing at `README.md:456-477` for anyone who wants the plugin anyway. **A spec that closes the
Xcode gap changes this row**, and names D14 when it does.

**Amended 2026-09-10 — §11.2, §11.4.** 001 §11.2 is closed. `XcodeBuildToolPlugin` resolves bare
template names through routes 2 and 3 and exports `SOURCERY_TEMPLATES`, and `run-xcode-checks.sh`
gates it on every push. D14 said a spec closing the Xcode gap changes §5.1's row and names D14: this
amendment does both. One of D14's two degradations survives — the source closure — and it is a
paragraph in `references/spm-plugin.md` rather than a lane decision.

**D15 — One repository, and it is this one.** The skill could live in a
`swift-sourcery-templates-skills` repository of its own, and one repository can publish any number of
skills through every channel in §4 — `skills/<a>/` and `skills/<b>/` side by side, `npx skills add
… --skill <name>` for a subset, one marketplace entry per plugin or one plugin carrying several
skills, each addressed as `/<plugin>:<skill>`. The Appllama repository ships two that way. So the
question is not whether a second repository *could* work.

It is what happens to checks AC6, SC6 and SC7. All three compare the skill's text against a file in this
repository — the registry, the plugin source, `Commands.swift`. In one repository they run on the
push that breaks them. Split across two, the skills repository can only check against a pinned or
freshly cloned copy of the templates, so a registry edit here would go green here and break there,
and the break would surface on the skills repository's next push or on a schedule. That converts a
synchronous gate into a delayed one, and being current with the templates is the skill's entire
value.

If a separate presence is wanted later for discovery, the way to get it without splitting the gate is
a marketplace repository whose plugin entry uses a `git-subdir` source pointing into this repository —
which is what `anthropics/claude-plugins-official` does for every third-party plugin it lists.

## 9. Non-goals

- **Making the registry enforceable by the type system.** §2.4: `annotations["Foo"]` is
  SourceryRuntime's API and cannot be removed. Check AC1 is the enforcement, and it is a grep.
- **Warning on unrecognized annotations.** §2.5, D4 — only near-misses of known verbs and retired names draw a response.
- **Rendering anything but the annotation table.** The exported-variable table
  (`README.md:432-455`) and the `mock-templates` flag list are the plugin's and the CLI's, and each
  would need its own extractor. Checks SC6 and SC7 compare names without generating prose.
- **A contributor-facing skill.** Editing templates, recording snapshots, the release procedure:
  CONTRIBUTING and AGENTS.md.
- **A `.claude/skills/` copy for this repository.** The skill teaches adopting the templates; an
  agent working here is editing them.
- **Shipping the skill in the release artifact bundle.** `Scripts/assemble-release.sh` assembles what
  a generating repository executes. A skill is installed by one of the four channels in §4.
- **An MCP server.** The reference repository ships `.mcp.json` because its skill drives a hosted
  service. Both lanes here are a binary and a config file.

---

## 10. Open questions

**10.1 — Does a plugin rooted at the marketplace root load?** §4.5. Answered by phase B1, with D9's
fallback written down.

**10.2 — Does `npx skills add` need `skills/` at the root, or does it find `SKILL.md` anywhere?** The
CLI's documentation states no layout requirement, and `--list` is the cheap way to find out. The
answer does not change the plan — D11 puts the tree at the root either way — but it decides whether
`README.md` can promise the manual-copy path works from an arbitrary checkout depth.

**10.3 — Can a Sourcery 2.3.0 Swift template write to stderr?** §2.5 puts the option-level near-miss
message there because stdout is the generated file (`_header.swifttemplate:15`). Whether Sourcery
passes a template's `FileHandle.standardError` writes through to the build log is unverified, and
phase A4 depends on it. Two fallbacks, in order: emit the message as a `//` comment line at the top of
the generated file, which is visible but moves the snapshot and so has to be recorded; or raise
option near-misses to the same `throw` selectors get, accepting the false positives D3 and §2.5
describe. Measured in phase A4 before the mechanism is chosen.

**Answered 2026-09-10 in phase A4 — §11.5.** A Swift template cannot write to stderr: Sourcery 2.3.0
turns the write into `error: <template>: <text>`, exits 3 and writes no output file. The first
fallback is what shipped — a `//` comment line in the generated file.

**10.4 — Which release does phase A5 land in?** That A5 lands is decided (§8, D13). Which release is
not: it turns on when both reference consumers are next regenerated, since retiring `CreateMock`,
`TypeErase` and `ObjcProtocol` fails generation for any source still spelling them, and CONTRIBUTING
§"Cutting a release" already puts a `modaal-firebase-wrappers` regenerate in the release path. The
earliest candidate is the release after the one carrying phases A1–A4 and B1–B3.

---

## 11. Amendment — the lanes and the Xcode path after 0.8.0

Added 2026-09-10, measured against `f89052a`, the commit that merged `master` at 0.8.0 (`34635ed`)
into `spec/002-annotation-registry-and-agent-skill`. Nothing above this section is rewritten; §1.1,
§5.1, §7, §8 D14 and §10.3 each carry a line pointing here. Part B is written against this section
where it and an earlier one disagree.

### 11.1 Where Part A stands

| phase | commit | CI run |
| --- | --- | --- |
| A1 — the registry and `AnnotationAccess` | `f55a1c2` | 34414406801 |
| A2 — `Scripts/render-annotations.sh` and the README block | `8a125ec` | 34415144793, which covers A2 and A3: they were pushed together |
| A3 — `Tests/Checks/run-annotation-checks.sh` and the `annotations` job | `1eadcc8` | |
| A4 — exact matching, `rejectNearMisses`, the vocabulary fixtures | `8a7a319`, with `9f51353` and `4ddb717` after it | 34418399829, 34418726971, 34455827639 |
| the merge of 0.8.0 | `f89052a` | 34475105629, eight jobs |

Every one of those runs concluded `success`.

A5 has not been taken: `templates/Annotations/AnnotationRegistry.swift:274` still reads
`static let retired: [RetiredAnnotation] = []`, and `CreateMock`, `TypeErase` and `ObjcProtocol` are
still aliases of the three selectors. Part B has not started: there is no `skills/` directory.

### 11.2 The Xcode path is the same plugin, with four differences

001 §11.2 is closed. Both entry points call one body — `_createBuildCommands`, reached from
`Plugins/SourcerySwiftCodegenPlugin/SourcerySwiftCodegenPlugin.swift:1104` for SwiftPM and `:1215`
for Xcode — so the config copy, the line-level rewrite, the appended defaults, the `output:` check,
passthrough, determinism and template-name resolution are one implementation. A bare `- Mocks`
resolves in an Xcode project through routes 2 and 3 of `README.md:391-400` (`:1124`), and
`SOURCERY_TEMPLATES` is exported there (`:792`), which is what §5.1's row 2 and D14 said did not
happen. `Tests/Checks/run-xcode-checks.sh` builds an Xcode project on every push and gates all of it.

Four things differ, each a consequence of `XcodePluginContext` exposing no package graph:

| | SwiftPM (`BuildToolPlugin`) | Xcode (`XcodeBuildToolPlugin`) |
| --- | --- | --- |
| `${SOURCERY_SOURCES}` expands to | the target's own sources plus the recursive closure of its dependencies, one directory per module (`:1072`) | the target's own input-file directories, and nothing else (`:1195`) |
| a config is looked for in | the target's own directory (`:1062`) | every first-level directory under the project root that holds one of the target's input files (`:1167`) |
| exported variables | `SOURCERY_PACKAGE`, `SOURCERY_TARGET_<target>` and three `_DEP_` shapes, `GIT_ROOT` (`:1015`) | `SOURCERY_PROJECT` and `GIT_ROOT` only, plus `SOURCERY_TEMPLATES` and `SOURCERY_OUTPUT_DIR` from the shared body (`:1126`, `:792`, `:851`) |
| `args.testable` | inserted for a test target with exactly one root-package non-test target dependency; an ambiguous set is warned (`:1086`) | never inserted — `testableDefault` is `.notApplicable` (`:1204`) |

`XcodeTarget.dependencies` was measured empty on Xcode 26.5 for a package product dependency and for
a dependency on a sibling target in the same project, which is why row 1 cannot be closed and why no
`SOURCERY_TARGET_*` variable exists to name. So an author names every further directory themselves,
as an absolute path built from `${SOURCERY_PROJECT}`:

```yaml
sources:
  - ${SOURCERY_SOURCES}
  - ${SOURCERY_PROJECT}/Libraries/Kit/Sources
```

`README.md:475-497` documents this; `run-xcode-checks.sh`'s **closure** gate holds row 1 to what it
says, and its **hand-listed** gate builds the shape above.

### 11.3 The lane inventory Part B writes against

Six lanes run from `.github/workflows/ci.yml`, plus the `rules` job and the `changes` filter:

| lane | script | runner | gated on `changes` |
| --- | --- | --- | --- |
| annotations | `Tests/Checks/run-annotation-checks.sh` | ubuntu | no |
| fast | `Tests/Checks/run-checks.sh` | macOS | yes |
| CLI | `Tests/Checks/run-cli-checks.sh` | macOS | yes |
| plugin | `Tests/Checks/run-plugin-checks.sh` | macOS | yes |
| xcode | `Tests/Checks/run-xcode-checks.sh` | macOS | yes |
| full | `Tests/Examples/ExampleProjectSpm/test-ios.sh` | macOS | yes |

The filter is the `changes` job's `code_files` line: a push whose every path ends in `.md` sets
`code=false` and skips the five macOS lanes. §6.2 and §7's B2 row call for a filter edit; none is
needed, because `run-skill-checks.sh` reads markdown and its job belongs outside the filter, where
`annotations` and `rules` already are.

Two things 0.8.0 added that B1's `references/cli-lane.md` describes: `Scripts/engine-pin.sh` is the
upstream Sourcery pin of record, and `Package.swift`'s `sourcery` binaryTarget is this repository's
own artifact bundle, which carries the engine, `templates/` and the `mock-templates` CLI at one
version. The install snippet an adopter copies is `README.md:282`, at
`github.com/modaal-agent/swift-sourcery-templates` from 0.8.0.

### 11.4 What this amendment supersedes

| section | what it says | what is true at `f89052a` |
| --- | --- | --- |
| §5.1, row 2 | an Xcode project goes to the CLI lane, because `${SOURCERY_SOURCES}` derives no closure and bare template names do not resolve | bare names resolve and `SOURCERY_TEMPLATES` is exported; the row sends an Xcode project to the plugin lane and names §11.2's hand-listed `sources:` as the one thing the author writes |
| §8, D14 | the row above, held until 001 §11.2 closes, and: "A spec that closes the Xcode gap changes this row, and names D14 when it does" | §11.2 names it. What survives of D14 is the source closure, one paragraph of `references/spm-plugin.md` rather than a lane decision |
| §1.1, the range table | `README.md:456-477`, "the degraded Xcode path", 1,056 B | the section is `README.md:475-497`, and it documents one degradation, not a degraded path |
| §5.3 | `references/spm-plugin.md` carries "the Xcode degradation" | it carries §11.2's four-row table; the Xcode column is what an agent needs to write a working config |
| §6.2, §7's B2 row | "the `skills` job and the filter edit" | the job, and no filter edit — §11.3 |

### 11.5 What phase A4 measured, and where Part A departed from the plan

Recorded in the commit messages named below, and collected here because a reader of this directory
does not see them there.

- **§10.3 is answered, against its assumption.** A Swift template's stdout is the generated file, and
  Sourcery 2.3.0 turns any write to the template's stderr into `error: <template>: <text>`, exit 3,
  no output file. The option near-miss message is a `//` comment line in the generated file — the
  first fallback §10.3 names. Measured in `8a7a319`.
- **The near-miss error is its own type, not `MockError`.** `TypeErase.swifttemplate` includes
  nothing that declares `MockError`, and all three entry points call the scan (`4ddb717`).
- **The `AGENTS.md` rule landed in A4**, not B3 as §7 assigns it (`8a7a319`).
- **`Scripts/render-annotations.sh` has one target, not three.** §2.6's two skill files are created
  by B1, which adds them to `TARGETS` (`8a125ec`).
- **Sourcery propagates a declaration's annotations onto everything nested in it**, so a key on a
  protocol reappears on each method and each parameter. `rejectNearMisses` subtracts the parent's
  keys before reporting, or one misspelling is reported once per member (`8a7a319`).

### 11.6 Still open

- **Which release A5 lands in** — §10.4, unchanged by anything here.
- **Whether a plugin rooted at the marketplace root loads** — §10.1, answered by B1.
- **Whether `references/spm-plugin.md` documents `SOURCERY_TARGET_*` at all.** They exist only on the
  SwiftPM path, and `${SOURCERY_SOURCES}` reaches further than the one level they name
  (`README.md:465-466`). Decide it when B1 writes that file.
