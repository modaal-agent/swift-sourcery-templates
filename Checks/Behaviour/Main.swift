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

  // CurrentValueSubject by default: a subscriber attaching after the push still
  // sees the value. This is what a state stream's spec needs.
  let repository = MemoryRepositoryProtocolMock()
  repository.ownMemoriesSubject.send([MemoryDrop(id: "a")])
  var seen: [[MemoryDrop]] = []
  repository.ownMemories.sink { seen.append($0) }.store(in: &cancellables)
  expectEqual(seen, [[MemoryDrop(id: "a")]], "a state stream replays to a late subscriber")

  // A method returning a publisher is driven the same way.
  var completions = 0
  repository.delete(id: "a").sink(receiveCompletion: { _ in }, receiveValue: { completions += 1 })
    .store(in: &cancellables)
  repository.deleteSubject.send(())
  expectEqual(completions, 1, "a publisher-returning method is driven by its subject")
  expectEqual(repository.deleteCallCount, 1, "a publisher-returning method counts its calls")

  // No default value for the element type, so the subject is a Passthrough and
  // the mock still compiles and delivers.
  let events = MemoryEventStreamingMock()
  var latest: [MemoryDrop] = []
  events.latestDrop.sink { latest.append($0) }.store(in: &cancellables)
  events.latestDropSubject.send(MemoryDrop(id: "b"))
  expectEqual(latest, [MemoryDrop(id: "b")], "an element type with no default falls back to a passthrough subject")

  // The per-member override.
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

func checkSendableMock() {
  // A protocol refining Sendable produces a mock that can cross an isolation
  // boundary — the conformance is `@unchecked`, which is the accurate statement
  // for a test double holding mutable counters.
  let analytics = AnalyticsTrackingMock()
  let sendable: any Sendable = analytics
  expect(sendable is AnalyticsTrackingMock, "a Sendable protocol produces a Sendable mock")
}

// MARK: - Entry point

@main
enum BehaviourChecks {
  static func main() async {
    print("behaviour checks")
    checkCallCountingAndHandlers()
    await checkAsync()
    await checkNonisolatedMembers()
    checkCombineStreams()
    checkComposition()
    checkSendableClosureParameters()
    checkSendableMock()

    if failures.isEmpty {
      print("  all behaviour checks passed")
    } else {
      print("  \(failures.count) behaviour check(s) failed")
      exit(1)
    }
  }
}
