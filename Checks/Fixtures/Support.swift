// Types the fixture protocols are written against.
//
// Stand-ins for a consumer's domain types: no annotations, no mocks generated
// from them. They exist so the fixtures can mirror real protocol shapes without
// dragging UIKit, AVFoundation or a product module into the checks.

import Combine
import Foundation

// MARK: - Domain mirrors

public struct UserSummary: Equatable {
  public let uid: String
  public let displayName: String?

  public init(uid: String, displayName: String?) {
    self.uid = uid
    self.displayName = displayName
  }
}

/// Deliberately has no default value, so a requirement of this type becomes a
/// mandatory initializer parameter on the generated mock.
public struct MemoryDrop: Equatable {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

// MARK: - Framework stand-ins

/// Stands in for `AVAudioSession.RecordPermission` / `UNAuthorizationStatus`:
/// an enum-typed read-only requirement with no synthesizable default.
public enum RecordPermission {
  case undetermined
  case denied
  case granted
}

public struct ViewShellChild {
  public let tag: String

  public init(tag: String) {
    self.tag = tag
  }
}

public protocol ThemeProviding: AnyObject {
  var accentName: String { get }
}

public final class StubThemeProvider: ThemeProviding, @unchecked Sendable {
  public let accentName: String

  public init(accentName: String = "default") {
    self.accentName = accentName
  }
}

// MARK: - Component support

/// The kind of object a composition level owns: built from collaborators the
/// level forwards, with a lifetime tied to the Component that holds it. Stands
/// in for WikiMemory's `FeedAudioPlayer`.
public final class FeedAudioPlayer {
  public let memoryRepository: MemoryRepositoryProtocol
  public let analytics: AnalyticsTracking

  public init(memoryRepository: MemoryRepositoryProtocol, analytics: AnalyticsTracking) {
    self.memoryRepository = memoryRepository
    self.analytics = analytics
  }
}

/// Supplies a member a parent does not itself declare, so a child conformance
/// can be satisfied by adaptation rather than forwarding.
public final class StubAudioSession: AudioSessionConfiguring {
  public var recordPermission: RecordPermission = .granted

  public init() {}

  public func activatePlayback() {}
  public func activateRecording() throws {}
  public func requestRecordPermission(_ handler: @escaping (Bool) -> Void) { handler(true) }
}
