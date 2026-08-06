// Combine shapes: publisher-typed requirements on variables and on methods,
// and the two subject kinds behind them.
//
// Without a smart default for `AnyPublisher`, every one of these becomes a
// stored property with a mandatory initializer parameter, and a test has no way
// to push a value through the mock.

import Combine
import Foundation

// MARK: - The default rule

/// `Output` has a default value (`[MemoryDrop]` → `[]`, `Bool` → `false`), so
/// each of these is backed by a `CurrentValueSubject`: a subscriber attaching
/// after the value was pushed still receives it, which is what a state stream
/// needs.
///
/// sourcery: CreateMock
public protocol MemoryRepositoryProtocol: AnyObject {
  var ownMemories: AnyPublisher<[MemoryDrop], Never> { get }
  var isRefreshing: AnyPublisher<Bool, Never> { get }
  func delete(id: String) -> AnyPublisher<Void, Error>
  func fetch(id: String) -> AnyPublisher<MemoryDrop?, Error>
}

/// `Output` has no default value, so the subject falls back to
/// `PassthroughSubject` — the alternative is a generated file that does not
/// compile.
///
/// sourcery: CreateMock
public protocol MemoryEventStreaming: AnyObject {
  var latestDrop: AnyPublisher<MemoryDrop, Never> { get }
}

// MARK: - The per-member override

/// sourcery: CreateMock
public protocol NotificationSignalling: AnyObject {
  /// A signal, not a state: a late subscriber must NOT receive the last one.
  /// sourcery: subject = "Passthrough"
  var friendGraphChanged: AnyPublisher<Void, Never> { get }

  /// State: seeded, and replayed to a late subscriber.
  /// sourcery: subject = "CurrentValue"
  var badgeCount: AnyPublisher<Int, Never> { get }
}
