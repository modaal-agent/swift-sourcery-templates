# Troubleshooting

One section per symptom. Each names what to read first, because most of these are visible in the
build log or in the generated file before they are visible as a compile error.

## `type 'XMock' does not conform to protocol 'Y'`

The mock is missing requirements the protocol inherits from a protocol that was not among the parsed
sources. The generator only sees the files it was pointed at; a refinement whose declaration it never
read contributes nothing to the mock, and no diagnostic is emitted, because from the generator's
position the protocol simply has fewer requirements.

- **Plugin lane:** put `- ${SOURCERY_SOURCES}` in the config's `sources:` list, or omit `sources:`
  altogether so the plugin appends the closure. In an Xcode project the closure stops at the target's
  own input directories, so add the other module's directory as an absolute path under
  `${SOURCERY_PROJECT}`.
- **CLI lane:** add the other module's directory as another `--sources` root.

Confirm by reading the generated file: the inherited requirement is either there or it is not.

## A generated type is missing, and the target compiles

The generated file was written somewhere the build does not collect from. A prebuild command's
outputs are collected only from the directory it declared, so a config naming its own `output:`
produces a file nothing compiles.

Omit `output:`, or write `output: ${SOURCERY_OUTPUT_DIR}`. Any other directory fails the build
naming both paths — if the build did not fail, the config is not the one that ran; check that the
config file is in the target's own source directory and that its name matches `*.sourcery*.yml`.

## `` `createmock` on `Foo` is not `ProtocolMock` ``

Generation failed because a selector's spelling differs from the registry's only in case. Names are
matched exactly. Write the canonical spelling — the message names it.

The legacy spellings `CreateMock`, `ObjcProtocol` and `TypeErase` are still accepted; a spelling
that differs from one of those in case is not.

## A misspelled option, and a comment in the generated file

A near-miss of an *option* does not fail generation. It writes one line into the generated file:

```swift
// sourcery-templates: `skipargumentrecording` on `Foo.save(_:)` is not `skipArgumentRecording` — annotation names are matched exactly, including case
```

The mock is generated without that behaviour. Fix the spelling and regenerate; the line disappears.
Options are treated more gently than selectors because a repository may legitimately own a key of
its own with the same name for a different template.

## A protocol generates no mock, and nothing is reported

Two causes, in the order worth checking:

1. **The declaration carries no selector.** A protocol with no `/// sourcery: ProtocolMock` is not a
   candidate. For a protocol you do not own, annotate an empty extension in an annotations
   directory.
2. **The file is not under any scanned root.** Read the build log: the plugin prints every directory
   it passed to the generator. On the CLI lane, `--sources` is the whole set.

An annotation the templates do not recognize at all draws no response by design — it may belong to
another template in the same run.

## The generator will not run — unidentified developer

The downloaded engine binary is quarantined by Gatekeeper. Clear the attribute on the resolved
binary:

```bash
xattr -dr com.apple.quarantine <path to the resolved artifact bundle>/sourcery/bin/sourcery
```

Under the plugin the path is inside the build system's `SourcePackages/artifacts/` directory; on the
CLI lane it is the bundle that was unzipped.

## A Combine test hangs, or a continuation resumes twice

An `AnyPublisher` member is backed by a `PassthroughSubject`, for a property and for a method alike.
It emits what the test sends and nothing else, so a subscriber attaching after a send has missed it.

Three fixes, in order of preference:

1. subscribe first, then send;
2. return a replaying subject from the member's handler:

   ```swift
   let state = CurrentValueSubject<UserSummary?, Never>(me)
   mock.meStreamGetHandler = { state.eraseToAnyPublisher() }
   ```

3. annotate the declaration `subject = "CurrentValue"` where every test wants the seeded form.

A double that seeded itself would emit a value nobody wrote the moment the code under test
subscribes, and turn the test's own `send` into a second element — which is what resumes a bridging
continuation twice.

## `value of type 'XMock' has no member '<name>'`

The prefix is the **declared name**, verbatim, with backticks dropped: `func perform1_0()` gives
`perform1_0CallCount`, not `perform10CallCount`; `func ID()` gives `IDCallCount`. Older releases
applied a case-and-underscore transform to methods and not to properties, so a name a test learned
from a generated file made before the templates were bumped can be stale — regenerate, and read the
member off the file.

For an **overloaded** requirement the name carries the argument labels: `func end(atDocument
document:)` gives `endAtDocument`. Only the overload with the fewest parameters keeps the plain
name, and the requirement set includes what the protocol inherits, so a refinement can put a
requirement into an overload group that its own declaration does not show. `/// sourcery: methodName
= "customName"` pins a member's name.

## A property's `<var>GetCount` moved and the test did not read it

Every property requirement counts its reads, so an assertion that reads `mock.draft` moves
`draftGetCount` itself. Read `mock._draft` — the store behind the accessors — to read or seed the
value without moving a counter.

## `<name>SubscribeCount` is zero and the stream delivered

`<var>GetCount` counts the code under test *asking* for the publisher; `<name>SubscribeCount` counts
it *subscribing*. A code path that reads the member and stores it without subscribing moves the
first and not the second, and nothing is delivered to it.

`<name>OutputCount` is the third question: it counts delivery, not sending. A value sent while
nobody is subscribed is dropped by the `PassthroughSubject` and counts nothing. Where a method's
`<method>Handler` is set, the member never reaches the deferred subject at all, so
`<method>SubscribeCount` stays at zero by design.

## `<method>Args` does not exist

Argument recording is skipped for three shapes: a method whose parameters are all closures, a
generic method, and anything annotated `skipArgumentRecording` on the method or on its protocol.
`skipArgumentRecording` drops `<name>Outputs` and `<name>Events` too, for the same reason.

Assert through `<method>Handler` instead — it receives every parameter, closures included.

A closure parameter is deliberately never recorded: storing an escaping closure would keep the
caller's captures alive for as long as the mock, which a leak spec reads as a retain by the code
under test.

## A Component fails generation, naming a member

`static` requirements, `init` requirements, `subscript` requirements and associated types cannot be
discharged by forwarding to a stored instance, so generation fails rather than emitting a class that
will not conform.

Hand-write that member, or annotate the protocol `DuetComponent, owns` and write the subclass of the
emitted `<X>ComponentBase` that holds it.

## Swift 6 rejects the test body

A mock of a non-isolated protocol is a non-Sendable `final class`. Constructing it on the main actor
and then calling a `nonisolated async` member crosses an isolation boundary with a non-Sendable
value.

Make the test body non-isolated. The mock's isolation follows the protocol's by design, so the fix
is on the test's side rather than the mock's.

## Subclassing a mock does not compile

Mock classes are `final`. Set a handler instead — every method and every property has one, and a
handler can hold whatever a subclass would have overridden.

## The build succeeds and the committed generated file is stale

Only the CLI lane can produce this: the plugin regenerates on every build. Run `mock-templates
validate` — it names which input changed, or reports the body as hand-edited. Add that command to
CI, which is what the fingerprint block exists for.
