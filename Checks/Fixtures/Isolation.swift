// Concurrency shapes: global-actor isolation, `nonisolated` requirements,
// `async`, `throws`, and `Sendable` refinement.
//
// Every protocol here is a shape taken from a consumer, not an invented one.
// The comments name where each came from.

import Combine
import Foundation

// MARK: - A `@MainActor` protocol, all members isolated

/// Shape of WikiMemory's `UserRepositoryProtocol`: a main-actor repository whose
/// surface is a state stream plus mutations returning publishers.
///
/// sourcery: CreateMock
@MainActor
public protocol UserRepositoryProtocol {
  var meStream: AnyPublisher<UserSummary?, Never> { get }
  func bootstrap(displayName: String?) -> AnyPublisher<Void, Error>
  func registerDevice(token: String, platform: String) -> AnyPublisher<Void, Error>
}

// MARK: - A `@MainActor` protocol with a `nonisolated` requirement

/// The construct a subtree port takes (doc-15 §1.4 constraint 4: the node
/// declares a narrow nonisolated capability, the app adapts to it). The mock
/// must restate `nonisolated` on the member *and* on its call counter, or the
/// generated file does not build under complete concurrency checking.
///
/// sourcery: CreateMock
@MainActor
public protocol PushNotificationRepositoryProtocol: AnyObject {
  var isNotificationsEnabled: Bool { get }
  var authorizationStatus: RecordPermission { get }

  /// Called from the permission prompt's completion, off the main actor.
  nonisolated func requestPermission()

  /// A nonisolated read: the adapter exposes it to a non-isolated node.
  nonisolated var installationId: String { get }

  func setNotificationsEnabled(_ enabled: Bool)
  func deregisterCurrentDevice() -> AnyPublisher<Void, Error>
}

// MARK: - `async` and `throws`

/// Shape of the app's staging/upload seams: async work with and without
/// throwing, and a synchronous throwing sibling.
///
/// sourcery: CreateMock
public protocol MediaStaging {
  func stage(fileName: String) async -> String
  func upload(fileName: String) async throws -> URL
  func discardAll() async
  func validate(fileName: String) throws
}

// MARK: - `Sendable` refinement

/// A protocol refining `Sendable` — the mock's call counters are mutable stored
/// properties, so the conformance has to be `@unchecked` to compile at all.
///
/// sourcery: CreateMock
public protocol AnalyticsTracking: Sendable {
  func track(_ name: String)
  func identify(uid: String)
  func reset()
}

// MARK: - Member-level isolation, non-isolated protocol

/// Shape of WikiMemory's `<X>Buildable`: the protocol is not isolated, the mount
/// method is. A non-isolated witness satisfies a `@MainActor` requirement, so
/// the generated mock stays callable from a non-isolated test body — this
/// fixture exists to keep that true.
///
/// sourcery: CreateMock
public protocol TimelineBuildable: AnyObject {
  @MainActor
  func build(withTag tag: String) -> ViewShellChild
}

// MARK: - Escaping closure parameters (0.2.13 regression guard)

/// Shape of `AudioSessionConfiguring`: a throwing activation plus a permission
/// request whose completion is captured and dispatched later.
///
/// sourcery: CreateMock
public protocol AudioSessionConfiguring: AnyObject {
  func activatePlayback()
  func activateRecording() throws
  var recordPermission: RecordPermission { get }
  func requestRecordPermission(_ handler: @escaping (Bool) -> Void)
}

// MARK: - `@Sendable` closure parameters

/// A completion the protocol declares as `@Sendable`, because the caller's
/// closure crosses an isolation boundary.
///
/// Dropping the attribute does not break conformance — a witness taking a
/// non-Sendable closure is the more general one — and it does not break
/// capturing the closure either. What it breaks is handing the captured closure
/// to anything `@Sendable`-constrained: the type has lost its Sendability. So
/// the mock restates both attributes in the signature and in the handler type.
///
/// sourcery: CreateMock
public protocol UploadScheduling: AnyObject {
  func schedule(fileName: String, completion: @escaping @Sendable (Bool) -> Void)
}
