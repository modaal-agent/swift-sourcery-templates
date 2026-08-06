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
