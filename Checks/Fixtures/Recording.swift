// What the recorded-argument arrays (`<method>Args`) have to get right beyond
// the plain parameter lists the other fixtures already carry — every mocked
// method in this directory contributes its own array to the snapshot, so the
// shapes here are the ones where that array is not simply `[T]`.
//
// Three of them: storage that a nonisolated member may mutate, an `inout`
// parameter, and the opt-out — declared on one method, or on the whole
// protocol.

import Foundation

// MARK: - Isolation

/// A `@MainActor` protocol whose reporting members are `nonisolated`, the same
/// subtree-port shape `PushNotificationRepositoryProtocol` carries — the node
/// reports from wherever it runs, the app adapts.
///
/// The recorded-argument arrays of those members are `nonisolated(unsafe)` for
/// the reason their call counters are: a nonisolated member cannot mutate
/// main-actor isolated storage.
///
/// sourcery: CreateMock
@MainActor
public protocol DiagnosticsReporting: AnyObject {
  /// Two parameters, one of them optional: recorded as one labelled tuple per
  /// call, so a spec reads `reportArgs.last?.detail` rather than correlating
  /// two arrays by index.
  nonisolated func report(_ code: String, detail: String?)

  /// `inout`: the parameter declaration keeps it, and the recorded element type
  /// drops it — `[inout Int]` is not a type, and what the mock records is the
  /// value it was handed on entry.
  nonisolated func accumulate(into total: inout Int)

  /// No parameters, so no array is generated. The call counter is the whole
  /// record of this call.
  func flush()
}

// MARK: - The opt-out

/// A level that hands the observer an object whose lifetime a churn spec
/// asserts — the reference app's `FeedAudioPlayer`, owned by `MainComponent` and
/// expected to deallocate when the level detaches.
///
/// `attach` records, and the mock therefore holds the player until the spec
/// clears `attachArgs`. `adopt` is annotated, so it does not — that is the
/// whole difference, and it is why the annotation exists rather than a blanket
/// rule about reference types, which the template cannot tell apart from value
/// types anyway.
///
/// sourcery: CreateMock
public protocol PlaybackObserving: AnyObject {
  func attach(_ player: FeedAudioPlayer)

  /// sourcery: skipArgumentRecording
  func adopt(_ player: FeedAudioPlayer)
}

/// The same opt-out on the type, for a protocol whose whole surface hands over
/// objects a spec measures the lifetime of. No method of this mock generates an
/// array; every one still counts its calls and runs its handler.
///
/// sourcery: CreateMock, skipArgumentRecording
public protocol PlaybackRetaining: AnyObject {
  func retain(_ player: FeedAudioPlayer)
  func release(tag: String)
}
