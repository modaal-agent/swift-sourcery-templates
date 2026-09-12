// Combine shapes: publisher-typed requirements on variables and on methods,
// and the two subject kinds behind them.
//
// Without a smart default for `AnyPublisher`, every one of these becomes a
// stored property with a mandatory initializer parameter, and a test has no way
// to push a value through the mock.

import Combine
import Foundation

// MARK: - The default rule

/// Every member here is backed by a `PassthroughSubject`, whether it is a
/// variable or a method and whether or not `Output` has a default value
/// (`[MemoryDrop]` → `[]`, `Bool` → `false`, `String` → `""`). The double emits
/// what the test sends it; a stream that replays comes from the member's own
/// closure — `ownMemoriesGetHandler`, `shareHandler` — or from the annotation on
/// `token` below.
///
/// sourcery: CreateMock
public protocol MemoryRepositoryProtocol: AnyObject {
  var ownMemories: AnyPublisher<[MemoryDrop], Never> { get }
  var isRefreshing: AnyPublisher<Bool, Never> { get }
  func delete(id: String) -> AnyPublisher<Void, Error>
  func fetch(id: String) -> AnyPublisher<MemoryDrop?, Error>
  func share(id: String) -> AnyPublisher<String, Error>

  /// The override reaches a method too: this one answers `""` on subscribe.
  /// sourcery: subject = "CurrentValue"
  func token() -> AnyPublisher<String, Error>
}

/// `Output` has no default value. It takes the same subject as one that does:
/// there is nothing left for a default value to decide.
///
/// sourcery: CreateMock
public protocol MemoryEventStreaming: AnyObject {
  var latestDrop: AnyPublisher<MemoryDrop, Never> { get }
}

// MARK: - The per-member override

/// sourcery: CreateMock
public protocol NotificationSignalling: AnyObject {
  /// A signal, not a state: a late subscriber must NOT receive the last one.
  /// The annotation states the default rather than changing it.
  /// sourcery: subject = "Passthrough"
  var friendGraphChanged: AnyPublisher<Void, Never> { get }

  /// State: seeded, and replayed to a late subscriber.
  /// sourcery: subject = "CurrentValue"
  var badgeCount: AnyPublisher<Int, Never> { get }
}

// MARK: - What a stream member records

/// `<name>Outputs` on a publisher member and `<name>Events` on an `AnyObserver`
/// one record what crossed the member, the way `<method>Args` records what a
/// call carried (`specs/004-mock-member-naming/spec.md` D13). They sit under the
/// same opt-out and for the same reason: a recorded value lives as long as the
/// mock, and when the value is an object a churn or leak spec measures the
/// deallocation of, that retain reads as a leak in the code under test.
///
/// `frames` records; `rawFrames` is annotated and does not. Both still count
/// their outputs and run `<name>OutputHandler`.
///
/// sourcery: CreateMock
public protocol FrameStreaming: AnyObject {
  var frames: AnyPublisher<FeedAudioPlayer, Never> { get }

  /// sourcery: skipArgumentRecording
  var rawFrames: AnyPublisher<FeedAudioPlayer, Never> { get }

  /// The same on a method.
  /// sourcery: skipArgumentRecording
  func replay(tag: String) -> AnyPublisher<FeedAudioPlayer, Never>
}

/// The opt-out on the type reaches every stream member of it, as it reaches
/// every method's arguments.
///
/// sourcery: CreateMock, skipArgumentRecording
public protocol FrameRetaining: AnyObject {
  var frames: AnyPublisher<FeedAudioPlayer, Never> { get }
  func replay(tag: String) -> AnyPublisher<FeedAudioPlayer, Never>
}
