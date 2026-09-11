// Runtime checks over the generated mocks: what a test actually does with them.
//
// A typecheck proves the file compiles; these prove the mock counts calls, runs
// handlers, suspends where the protocol says it suspends, and delivers values
// pushed into its subjects. Plain assertions, no test framework — the harness is
// a single executable so the checks stay dependency-free and run in a second.

import Combine
import Foundation

// MARK: - Reporting

nonisolated(unsafe) var failures: [String] = []

func expect(_ condition: Bool, _ what: String) {
  if condition {
    print("  ok    \(what)")
  } else {
    print("  FAIL  \(what)")
    failures.append(what)
  }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
  expect(actual == expected, "\(what) — expected \(expected), got \(actual)")
}

// MARK: - Checks

@MainActor
func checkCallCountingAndHandlers() {
  // `recordPermission` has no synthesizable default, so it is an initializer
  // parameter — the shape every `<X>Dependency` member takes.
  let mock = AudioSessionConfiguringMock(recordPermission: .undetermined)

  mock.activatePlayback()
  mock.activatePlayback()
  expectEqual(mock.activatePlaybackCallCount, 2, "call count increments")

  var captured: [Bool] = []
  mock.requestRecordPermissionHandler = { handler in handler(true) }
  mock.requestRecordPermission { captured.append($0) }
  expectEqual(captured, [true], "@escaping completion is captured and invoked")

  mock.recordPermission = .granted
  expect(mock.recordPermission == .granted, "a read-only requirement is settable on the mock")

  struct Boom: Error {}
  mock.activateRecordingHandler = { throw Boom() }
  var threw = false
  do { try mock.activateRecording() } catch { threw = true }
  expect(threw, "a throwing handler propagates out of the mock")
}

/// Deliberately *not* `@MainActor`: `MediaStaging` is a non-isolated protocol,
/// so its mock is a non-Sendable class. Constructing it on the main actor and
/// then calling a nonisolated `async` member sends it across an isolation
/// boundary, which the Swift 6 language mode rejects. A test drives such a mock
/// from a non-isolated context.
func checkAsync() async {
  let mock = MediaStagingMock()

  mock.stageHandler = { fileName in "staged-\(fileName)" }
  let staged = await mock.stage(fileName: "clip.m4a")
  expectEqual(staged, "staged-clip.m4a", "an async method returns its handler's value")
  expectEqual(mock.stageCallCount, 1, "an async method counts its calls")

  // The handler is an `async` closure, so it can suspend — which is the whole
  // point of threading `async` through: a spec controls when the call returns,
  // not merely what it returns. Without `async` on the handler type the body
  // below does not compile, because `gate.wait()` cannot be awaited from it.
  let gate = Gate()
  mock.uploadHandler = { fileName in
    await gate.wait()
    return URL(string: "https://example.invalid/\(fileName)")!
  }
  // The task captures only the actor, so the non-Sendable mock stays put.
  Task { await gate.open() }
  let url = try? await mock.upload(fileName: "clip.m4a")
  expectEqual(url?.lastPathComponent, "clip.m4a", "an async handler may suspend before returning")

  struct Boom: Error {}
  mock.uploadHandler = { _ in throw Boom() }
  var threw = false
  do { _ = try await mock.upload(fileName: "x") } catch { threw = true }
  expect(threw, "an async throwing handler propagates")
}

/// One-shot suspension point, so the async check controls resumption itself
/// rather than sleeping.
actor Gate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var opened = false

  func wait() async {
    if opened { return }
    await withCheckedContinuation { continuation = $0 }
  }

  func open() {
    opened = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
func checkNonisolatedMembers() async {
  let mock = PushNotificationRepositoryProtocolMock(authorizationStatus: .granted)
  mock.installationId = "install-1"

  // The point of the `nonisolated` modifier surviving into the mock: this call
  // is legal from a context that is not the main actor.
  await Task.detached {
    mock.requestPermission()
    expectEqual(mock.installationId, "install-1", "a nonisolated read works off the main actor")
  }.value

  expectEqual(mock.requestPermissionCallCount, 1, "a nonisolated method counts its calls")
}

@MainActor
func checkCombineStreams() {
  var cancellables: Set<AnyCancellable> = []

  // PassthroughSubject by default, for a variable and for a method alike: the
  // double emits what the test sends it, and nothing else. A subscriber that
  // attaches after a send has missed it.
  let repository = MemoryRepositoryProtocolMock()
  repository.ownMemoriesSubject.send([MemoryDrop(id: "a")])
  var seen: [[MemoryDrop]] = []
  repository.ownMemories.sink { seen.append($0) }.store(in: &cancellables)
  expectEqual(seen, [], "the default subject does not replay to a late subscriber")
  repository.ownMemoriesSubject.send([MemoryDrop(id: "b")])
  expectEqual(seen, [[MemoryDrop(id: "b")]], "a variable delivers what the test sends after subscribe")

  // Replay is the test's to supply, through the closure every publisher member
  // has. This is the RxSwift branch's contract in Combine terms.
  let replaying = MemoryRepositoryProtocolMock()
  let state = CurrentValueSubject<[MemoryDrop], Never>([MemoryDrop(id: "seed")])
  replaying.ownMemoriesGetHandler = { state.eraseToAnyPublisher() }
  var replayed: [[MemoryDrop]] = []
  replaying.ownMemories.sink { replayed.append($0) }.store(in: &cancellables)
  expectEqual(replayed, [[MemoryDrop(id: "seed")]], "a get handler supplies a stream that replays")

  // A method returning a publisher is driven the same way.
  var completions = 0
  repository.delete(id: "a").sink(receiveCompletion: { _ in }, receiveValue: { completions += 1 })
    .store(in: &cancellables)
  repository.deleteSubject.send(())
  expectEqual(completions, 1, "a publisher-returning method is driven by its subject")
  expectEqual(repository.deleteCallCount, 1, "a publisher-returning method counts its calls")

  // An element type with no default value takes the same subject as one with a
  // default: there is nothing left for a default value to decide.
  let events = MemoryEventStreamingMock()
  var latest: [MemoryDrop] = []
  events.latestDrop.sink { latest.append($0) }.store(in: &cancellables)
  events.latestDropSubject.send(MemoryDrop(id: "b"))
  expectEqual(latest, [MemoryDrop(id: "b")], "an element type with no default is driven by its subject")

  // A method says nothing until the test answers. A seeded subject would answer
  // `""` on subscribe — a server response the test never wrote — and then
  // deliver a second element when the test sends the real one.
  var shared: [String] = []
  repository.share(id: "a").sink(receiveCompletion: { _ in }, receiveValue: { shared.append($0) })
    .store(in: &cancellables)
  expectEqual(shared, [], "a request answers nothing until the test sends")
  repository.shareSubject.send("link")
  expectEqual(shared, ["link"], "a request delivers exactly what the test sent")

  // …and the override reaches a method, for the double that should answer.
  var tokens: [String] = []
  repository.token().sink(receiveCompletion: { _ in }, receiveValue: { tokens.append($0) })
    .store(in: &cancellables)
  expectEqual(tokens, [""], "`subject = CurrentValue` on a method answers on subscribe")

  // The per-member override, for a declaration where every test wants the seeded
  // form. `Passthrough` states the default explicitly.
  let signals = NotificationSignallingMock()
  signals.friendGraphChangedSubject.send(())
  var signalled = 0
  signals.friendGraphChanged.sink { signalled += 1 }.store(in: &cancellables)
  expectEqual(signalled, 0, "`subject = Passthrough` does not replay")

  signals.badgeCountSubject.send(3)
  var badges: [Int] = []
  signals.badgeCount.sink { badges.append($0) }.store(in: &cancellables)
  expectEqual(badges, [3], "`subject = CurrentValue` replays")

  // The getter handler still wins over the subject.
  repository.isRefreshingGetHandler = { Just(true).eraseToAnyPublisher() }
  var refreshing: [Bool] = []
  repository.isRefreshing.sink { refreshing.append($0) }.store(in: &cancellables)
  expectEqual(refreshing, [true], "a get handler overrides the subject")
  expectEqual(repository.isRefreshingGetCount, 1, "a variable get is counted")
}

/// What the construct a publisher member hands back records
/// (`specs/004-mock-member-naming/spec.md` §2.7). The member returns a `Deferred`
/// the mock owns, so it can tell "asked for the stream" from "subscribed" from
/// "was actually sent something" — three facts that were one counter before.
func checkPublisherCounting() {
  var cancellables: Set<AnyCancellable> = []

  let repository = MemoryRepositoryProtocolMock()
  _ = repository.ownMemories
  expectEqual(repository.ownMemoriesGetCount, 1, "reading the member counts a read")
  expectEqual(repository.ownMemoriesSubscribeCount, 0, "and no subscription")

  let held = repository.ownMemories
  var seen: [[MemoryDrop]] = []
  held.sink { seen.append($0) }.store(in: &cancellables)
  expectEqual(repository.ownMemoriesSubscribeCount, 1, "subscribing counts a subscription")

  // Delivery is counted, not sending: a `PassthroughSubject` drops a value that
  // reaches no subscriber, and `<name>OutputCount` is how a test sees that.
  let quiet = MemoryRepositoryProtocolMock()
  quiet.ownMemoriesSubject.send([MemoryDrop(id: "unheard")])
  expectEqual(quiet.ownMemoriesOutputCount, 0, "a send with nobody subscribed counts no output")

  repository.ownMemoriesSubject.send([MemoryDrop(id: "a")])
  expectEqual(repository.ownMemoriesOutputCount, 1, "a delivered value counts one output")
  expectEqual(repository.ownMemoriesOutputs, [[MemoryDrop(id: "a")]], "and is recorded")

  // A publisher records per subscription, so one send to two subscribers counts
  // and records twice.
  repository.ownMemories.sink { _ in }.store(in: &cancellables)
  expectEqual(repository.ownMemoriesSubscribeCount, 2, "a second subscription counts")
  repository.ownMemoriesSubject.send([MemoryDrop(id: "b")])
  expectEqual(repository.ownMemoriesOutputCount, 3, "one send to two subscribers counts twice")

  repository.ownMemoriesSubject.send(completion: .finished)
  expectEqual(repository.ownMemoriesCompletionCount, 2, "a completion is counted per subscription")

  // Cancellation, counted separately from the subscription that produced it.
  let cancelling = MemoryRepositoryProtocolMock()
  var token: AnyCancellable? = cancelling.ownMemories.sink { _ in }
  expectEqual(cancelling.ownMemoriesSubscribeCancelCount, 0, "an open subscription counts no cancel")
  token?.cancel()
  token = nil
  expectEqual(cancelling.ownMemoriesSubscribeCancelCount, 1, "cancelling counts a cancel")

  // The handler is read when the code under test subscribes, not when it reads
  // the member — so a handler seeded after the publisher was captured decides
  // the stream. That is what the `Deferred` buys over erasing the subject.
  let late = MemoryRepositoryProtocolMock()
  let captured = late.ownMemories
  late.ownMemoriesGetHandler = { Just([MemoryDrop(id: "late")]).eraseToAnyPublisher() }
  var lateSeen: [[MemoryDrop]] = []
  captured.sink { lateSeen.append($0) }.store(in: &cancellables)
  expectEqual(lateSeen, [[MemoryDrop(id: "late")]], "a handler seeded after capture decides the stream")
  expectEqual(late.ownMemoriesOutputCount, 1, "a handler-supplied stream's values are counted too")
  expectEqual(late.ownMemoriesCompletionCount, 1, "and its completion")

  // `<name>OutputHandler` runs after the counter and the recorder, and sees each
  // value as it lands — which is how a test drives a chain from inside it.
  let chained = MemoryRepositoryProtocolMock()
  var observed: [String] = []
  chained.shareOutputHandler = { value in
    observed.append(value)
    if value == "first" { chained.shareSubject.send("second") }
  }
  chained.share(id: "a").sink(receiveCompletion: { _ in }, receiveValue: { _ in }).store(in: &cancellables)
  chained.shareSubject.send("first")
  expectEqual(observed, ["first", "second"], "the output handler sees each value and can send the next")
  expectEqual(chained.shareOutputs, ["first", "second"], "and the recorder holds both")

  // A method keeps its handler at call time, where its arguments are.
  let handled = MemoryRepositoryProtocolMock()
  handled.shareHandler = { _ in Just("direct").setFailureType(to: Error.self).eraseToAnyPublisher() }
  var direct: [String] = []
  handled.share(id: "a").sink(receiveCompletion: { _ in }, receiveValue: { direct.append($0) })
    .store(in: &cancellables)
  expectEqual(direct, ["direct"], "a method handler still answers at call time")
  expectEqual(handled.shareSubscribeCount, 0, "and bypasses the deferred subject entirely")

  // The stream outlives the mock: the closure captures the subject directly and
  // the mock weakly, so only the counting stops.
  let subject: PassthroughSubject<[MemoryDrop], Never>
  var survivor: AnyPublisher<[MemoryDrop], Never>
  do {
    let short = MemoryRepositoryProtocolMock()
    subject = short.ownMemoriesSubject
    survivor = short.ownMemories
  }
  var afterRelease: [[MemoryDrop]] = []
  survivor.sink { afterRelease.append($0) }.store(in: &cancellables)
  subject.send([MemoryDrop(id: "c")])
  expectEqual(afterRelease, [[MemoryDrop(id: "c")]], "the stream still delivers after the mock is released")

  // `skipArgumentRecording` suppresses the recorder and nothing else.
  let frames = FrameStreamingMock()
  frames.frames.sink { _ in }.store(in: &cancellables)
  frames.rawFrames.sink { _ in }.store(in: &cancellables)
  let player = FeedAudioPlayer(memoryRepository: MemoryRepositoryProtocolMock(), analytics: AnalyticsTrackingMock())
  frames.framesSubject.send(player)
  frames.rawFramesSubject.send(player)
  expectEqual(frames.framesOutputs.count, 1, "an unannotated member records what it delivered")
  expectEqual(frames.rawFramesOutputCount, 1, "an opted-out member still counts its outputs")
  var raw: [FeedAudioPlayer] = []
  frames.rawFramesOutputHandler = { raw.append($0) }
  frames.rawFramesSubject.send(player)
  expectEqual(raw.count, 1, "and still runs its output handler")
}

@MainActor
func checkComposition() {
  // A Dependency mock takes its whole surface through the initializer, which is
  // what makes one protocol per composition level cheap to satisfy in a spec.
  let dependency = TimelineDependencyMock(
    analytics: AnalyticsTrackingMock(),
    audioSessionConfigurer: AudioSessionConfiguringMock(recordPermission: .granted),
    memoryRepository: MemoryRepositoryProtocolMock(),
    themeProvider: StubThemeProvider(accentName: "check"),
    userRepository: UserRepositoryProtocolMock())

  expectEqual(dependency.themeProvider.accentName, "check", "a Dependency mock forwards what it was built with")

  // The empty root Dependency has an empty mock, and it conforms.
  let root: RootDependency = RootDependencyMock()
  expect(root is RootDependencyMock, "an empty protocol produces an empty mock")

  // A composite protocol's mock carries the inherited requirements.
  let services = AppServicesRegisteringMock()
  let registration = services.registerURLHandler("tag", priority: 1)
  services.handlersDidRegister()
  expectEqual(services.registerURLHandlerCallCount, 1, "an inherited requirement is mocked on the composite")
  expectEqual(services.handlersDidRegisterCallCount, 1, "the composite's own requirement is mocked")

  // The registration token's `cancel()` is the deregistration, so the default
  // token counts it rather than trapping for want of a handler.
  registration.cancel()
  expectEqual(services.registerURLHandlerCancelCallCount, 1, "an AnyCancellable-returning method counts cancellation")
}

/// Takes a `@Sendable` closure, so it compiles only if the captured completion
/// kept its attribute through the mock's handler type.
func requiresSendableClosure(_ complete: @escaping @Sendable (Bool) -> Void) {
  complete(true)
}

/// A `@Sendable` closure cannot mutate a captured local `var`, so the result
/// goes in a box. This is the cost of `@Sendable` on a protocol requirement,
/// and it is why a consumer may legitimately choose not to declare one — the
/// template propagates what the protocol says rather than deciding for it.
final class ResultBox: @unchecked Sendable {
  var value: Bool?
}

@MainActor
func checkSendableClosureParameters() {
  let mock = UploadSchedulingMock()

  var captured: (@Sendable (Bool) -> Void)?
  mock.scheduleHandler = { _, completion in captured = completion }
  let box = ResultBox()
  mock.schedule(fileName: "clip.m4a") { box.value = $0 }

  // Without `@Sendable` on the handler's parameter type this line does not
  // compile: "converting non-Sendable function value to '@Sendable (Bool) ->
  // Void' may introduce data races".
  if let captured = captured { requiresSendableClosure(captured) }
  expectEqual(box.value, true, "a @Sendable completion survives capture and hand-off")
}

// MARK: - Recorded arguments

@MainActor
func checkArgumentRecording() {
  // One recordable parameter is stored under its own type: Swift has no
  // single-element labelled tuple to put it in.
  let analytics = AnalyticsTrackingMock()
  analytics.track("Memory Deleted")
  analytics.track("Memory Restored")
  expectEqual(analytics.trackArgs, ["Memory Deleted", "Memory Restored"], "recorded arguments keep call order")
  expectEqual(analytics.trackCallCount, analytics.trackArgs.count, "the array and the call counter agree")

  // Clearing the array is the whole reset story — there is no second
  // bookkeeping object for a spec to construct, wire up and reset.
  analytics.trackArgs = []
  expectEqual(analytics.trackArgs.count, 0, "a recorded-argument array is clearable")

  // Two or more are stored as one labelled tuple per call, so a spec reads a
  // single call's arguments together instead of correlating arrays by index.
  let services = AppServicesRegisteringMock()
  _ = services.registerURLHandler("push", priority: 3)
  expectEqual(services.registerURLHandlerArgs.last?.tag, "push", "a labelled tuple records the first parameter")
  expectEqual(services.registerURLHandlerArgs.last?.priority, 3, "a labelled tuple records the second")

  // A closure parameter is not recorded, so a method mixing one with a value
  // parameter records the value alone. The handler is what a spec uses to reach
  // the closure, and it still receives both.
  let uploads = UploadSchedulingMock()
  uploads.schedule(fileName: "clip.m4a") { _ in }
  expectEqual(uploads.scheduleArgs, ["clip.m4a"], "a closure parameter is skipped and its siblings are recorded")

  // Recording happens before the handler runs: a handler that throws does not
  // un-make the call.
  struct Boom: Error {}
  let staging = MediaStagingMock()
  staging.validateHandler = { _ in throw Boom() }
  try? staging.validate(fileName: "clip.m4a")
  expectEqual(staging.validateArgs, ["clip.m4a"], "a call whose handler throws is still recorded")
}

@MainActor
func checkNonisolatedArgumentRecording() async {
  let diagnostics = DiagnosticsReportingMock()

  // The arrays of a nonisolated member are `nonisolated(unsafe)`, which is what
  // lets the member record from off the main actor — the same assertion its
  // call counter makes.
  await Task.detached {
    diagnostics.report("E_NET", detail: nil)
  }.value
  expectEqual(diagnostics.reportArgs.last?.code, "E_NET", "a nonisolated member records off the main actor")
  expect(diagnostics.reportArgs.last?.detail == nil, "an optional parameter records its absence")

  // `inout` is dropped from the element type: what is recorded is the value the
  // caller passed in, and the handler still gets the reference.
  var total = 7
  diagnostics.accumulateHandler = { $0 += 1 }
  diagnostics.accumulate(into: &total)
  expectEqual(diagnostics.accumulateArgs, [7], "an inout parameter records its entry value")
  expectEqual(total, 8, "the inout parameter still reaches the handler by reference")
}

/// A fresh object whose lifetime the opt-out checks measure.
@MainActor
func makePlayer() -> FeedAudioPlayer {
  return FeedAudioPlayer(memoryRepository: MemoryRepositoryProtocolMock(), analytics: AnalyticsTrackingMock())
}

@MainActor
func checkArgumentRecordingOptOut() {
  let observer = PlaybackObservingMock()

  // A recorded argument lives as long as the mock holds it. That is a fact
  // about the recorder, not about the code under test — and it is the reason
  // the annotation exists.
  weak var attached: FeedAudioPlayer?
  do {
    let player = makePlayer()
    attached = player
    observer.attach(player)
  }
  expect(attached != nil, "a recorded argument is held by the mock")
  observer.attachArgs = []
  expect(attached == nil, "clearing the array releases it")

  // The annotated sibling never held it.
  weak var adopted: FeedAudioPlayer?
  do {
    let player = makePlayer()
    adopted = player
    observer.adopt(player)
  }
  expect(adopted == nil, "`skipArgumentRecording` on a method does not retain its argument")
  expectEqual(observer.adoptCallCount, 1, "an opted-out method still counts its calls")

  // On the protocol, the annotation opts every method out.
  let retainer = PlaybackRetainingMock()
  weak var retained: FeedAudioPlayer?
  do {
    let player = makePlayer()
    retained = player
    retainer.retain(player)
  }
  expect(retained == nil, "`skipArgumentRecording` on the protocol opts every method out")
  expectEqual(retainer.retainCallCount, 1, "an opted-out protocol still counts calls")
}

// MARK: - Components

@MainActor
func checkComponentForwarding() {
  let theme = StubThemeProvider(accentName: "forwarded")
  let parent = TimelineDependencyMock(
    analytics: AnalyticsTrackingMock(),
    audioSessionConfigurer: AudioSessionConfiguringMock(recordPermission: .granted),
    memoryRepository: MemoryRepositoryProtocolMock(),
    themeProvider: theme,
    userRepository: UserRepositoryProtocolMock())

  let component = TimelineComponent(dependency: parent)
  expect(component.themeProvider === theme, "a forwarder returns the parent's instance, not a copy")

  // The Component satisfies the protocol it forwards, which is what lets a
  // level hand itself to its own children.
  let asDependency: TimelineDependency = component
  expect(asDependency.themeProvider === theme, "the Component conforms to the Dependency it forwards")
}

@MainActor
func checkComponentOwnership() {
  let parent = MainDependencyMock(
    analytics: AnalyticsTrackingMock(),
    memoryRepository: MemoryRepositoryProtocolMock(),
    pushNotificationRepository: PushNotificationRepositoryProtocolMock(authorizationStatus: .granted),
    themeProvider: StubThemeProvider(accentName: "main"),
    userRepository: UserRepositoryProtocolMock())

  // The scope contract: an owned object's lifetime is the Component's. One
  // Component yields one instance; a second Component over the same parent
  // yields its own. A level that reallocated its Component per build would have
  // no scope at all, and this is the check that says so.
  let component = MainComponent(dependency: parent)
  expect(component.feedAudioPlayer === component.feedAudioPlayer, "an owned member is allocated once per Component")

  let sibling = MainComponent(dependency: parent)
  expect(component.feedAudioPlayer !== sibling.feedAudioPlayer, "a second Component owns its own instance")

  // The owned member is built from forwarders inherited from the generated
  // base — that is the whole reason the base exists.
  expect(component.feedAudioPlayer.memoryRepository === component.memoryRepository,
         "an owned member reads the generated forwarders")

  // A parent satisfies a child's Dependency, so the child's Component forwards
  // through two levels to the same object.
  let child = TimelineComponent(dependency: component)
  expect(child.memoryRepository === parent.memoryRepository, "a child Component forwards through its parent")
}

@MainActor
func checkComponentMutationAndEffects() async {
  let parent = CaptureDependencyMock(
    analytics: AnalyticsTrackingMock(),
    memoryRepository: MemoryRepositoryProtocolMock())
  parent.installationId = "install-7"

  let component = CaptureComponent(dependency: parent)

  component.draft = "half a memory"
  expectEqual(parent.draft, "half a memory", "a settable requirement forwards its setter")
  expectEqual(component.draft, "half a memory", "a settable requirement forwards its getter")

  // `nonisolated` survives forwarding, so the port stays callable from a
  // context that is not the main actor. That is the construct a subtree node
  // declares and the app adapts.
  await Task.detached {
    component.ping()
    expectEqual(component.installationId, "install-7", "a nonisolated forwarder works off the main actor")
  }.value
  expectEqual(parent.pingCallCount, 1, "a nonisolated forwarder reaches the parent")

  parent.stageHandler = { fileName, _ in URL(string: "https://example.invalid/\(fileName)")! }
  let staged = try? await component.stage("clip.m4a", retries: 2)
  expectEqual(staged?.lastPathComponent, "clip.m4a", "an async throws requirement forwards its effects")

  struct Boom: Error {}
  parent.stageHandler = { _, _ in throw Boom() }
  var threw = false
  do { _ = try await component.stage("x", retries: 0) } catch { threw = true }
  expect(threw, "a forwarded error reaches the caller")
}

func checkComponentParameterShapes() {
  let parent = StubRegistrationDependency()
  let component = RegistrationComponent(dependency: parent)

  component.submit("ABC123")
  expectEqual(parent.submitted, ["ABC123"], "an unlabelled parameter forwards without inventing a label")

  component.retry(after: 1.5, attempts: 3)
  expectEqual(parent.retries.first?.1, 3, "a parameter whose label differs from its name forwards by label")

  var total = 0
  component.accumulate(into: &total)
  expectEqual(total, 1, "an inout parameter forwards by reference")

  let encoded = try? component.encode(["k": "v"])
  expect(encoded != nil, "a generic method forwards with its clause stripped from the call")

  // `@Sendable` survives, so the closure may be handed to Sendable-constrained
  // code after the Component passed it along.
  let box = ResultBox()
  component.schedule(fileName: "clip.m4a") { box.value = $0 }
  expectEqual(parent.scheduled, ["clip.m4a"], "a @Sendable completion forwards")
  expectEqual(box.value, true, "the forwarded completion is the caller's")

  var ran = false
  component.withRetries { ran = true }
  expect(ran, "a rethrows method forwards as rethrows")
}

func checkComponentEffectfulProperty() async {
  let component = ProfileComponent(dependency: StubProfileDependency())
  let user = try? await component.currentUser
  expectEqual(user?.uid, "u1", "a `{ get async throws }` requirement forwards through an effectful getter")
  expect(component.cachedUser == nil, "a plain sibling requirement is unaffected")
}

func checkSendableMock() {
  // A protocol refining Sendable produces a mock that can cross an isolation
  // boundary — the conformance is `@unchecked`, which is the accurate statement
  // for a test double holding mutable counters.
  let analytics = AnalyticsTrackingMock()
  let sendable: any Sendable = analytics
  expect(sendable is AnalyticsTrackingMock, "a Sendable protocol produces a Sendable mock")
}

// MARK: - Property accessors

/// Every property requirement generates `GetCount`, `GetHandler` and a `_<var>`
/// store (`specs/004-mock-member-naming/spec.md` §2.5). What that has to get
/// right is which access moves which counter.
@MainActor
func checkPropertyCounting() {
  let mock = PropertyShapedMock(themeProvider: StubThemeProvider())

  // Construction seeds the store, so it counts no write. This is what keeps
  // `Mock(themeProvider:)` from arriving with `themeProviderSetCount == 1`.
  expectEqual(mock.themeProviderGetCount, 0, "construction counts no read")

  _ = mock.identifier
  _ = mock.identifier
  expectEqual(mock.identifierGetCount, 2, "a read of a stored requirement counts")

  mock._identifier = "seeded"
  expectEqual(mock.identifierGetCount, 2, "seeding through the store counts no read")
  expectEqual(mock.identifier, "seeded", "the accessor returns what the store holds")

  let draftMock = CaptureDependencyMock(analytics: AnalyticsTrackingMock(), memoryRepository: MemoryRepositoryProtocolMock())
  draftMock.draft = "typed"
  expectEqual(draftMock.draftSetCount, 1, "a write to a `{ get set }` requirement counts")
  expectEqual(draftMock.draftGetCount, 0, "a write counts no read")
  expectEqual(draftMock.draft, "typed", "the value written is the value read")
  expectEqual(draftMock.draftGetCount, 1, "and that read counts")

  draftMock._draft = "reseeded"
  expectEqual(draftMock.draftSetCount, 1, "seeding through the store counts no write")

  draftMock.draftGetHandler = { "from the handler" }
  expectEqual(draftMock.draft, "from the handler", "the handler wins over the store")
  expectEqual(draftMock._draft, "reseeded", "and leaves the store alone")
}

/// An effectful property requirement generates the accessor it declares
/// (`spec.md` §2.6). A stored property could not satisfy `{ get async throws }`
/// at all, so this is the first time the mock template witnesses one.
func checkEffectfulProperties() async {
  let mock = PropertyEffectfulMock(loader: StubThemeProvider())

  mock._token = "seeded"
  let token = await mock.token
  expectEqual(token, "seeded", "an `{ get async }` accessor suspends and returns the store")
  expectEqual(mock.tokenGetCount, 1, "and counts the read")

  struct Boom: Error {}
  mock.configGetHandler = { throw Boom() }
  var threw = false
  do { _ = try await mock.config } catch { threw = true }
  expect(threw, "a `{ get async throws }` handler propagates out of the accessor")
  expectEqual(mock.configGetCount, 1, "the read that threw is still counted")

  mock._secret = "quiet"
  let secret = try? mock.secret
  expectEqual(secret, "quiet", "a `{ get throws }` accessor returns the store when no handler throws")

  // The store is assignable even though the requirement is get-only, which is
  // how a test seeds a type with no synthesizable default.
  mock._loader = StubThemeProvider()
  expectEqual(mock.loaderGetCount, 0, "seeding the store of an effectful requirement counts no read")
}

// MARK: - Entry point

@main
enum BehaviourChecks {
  static func main() async {
    print("behaviour checks")
    checkCallCountingAndHandlers()
    checkPropertyCounting()
    await checkEffectfulProperties()
    await checkAsync()
    await checkNonisolatedMembers()
    checkCombineStreams()
    checkPublisherCounting()
    checkComposition()
    checkSendableClosureParameters()
    checkSendableMock()
    checkArgumentRecording()
    await checkNonisolatedArgumentRecording()
    checkArgumentRecordingOptOut()
    checkComponentForwarding()
    checkComponentOwnership()
    await checkComponentMutationAndEffects()
    checkComponentParameterShapes()
    await checkComponentEffectfulProperty()

    if failures.isEmpty {
      print("  all behaviour checks passed")
    } else {
      print("  \(failures.count) behaviour check(s) failed")
      exit(1)
    }
  }
}
