// The composition shapes these templates have to serve: a `<X>Dependency`
// protocol per level, the `<X>Component` that satisfies it, and the
// `<X>Buildable` that mounts it.
//
// Source: the WikiMemory reference app, where every composition level declares
// a Dependency protocol naming exactly what it consumes and a Component that
// forwards or owns each member. Generated mocks are what makes one protocol per
// level cheap enough to be the rule, so the shape is checked here.
//
// `CreateMock` and `DuetComponent` are independent and compose: the first
// generates the test double a spec drives, the second generates the production
// Component that forwards to the parent. A protocol carrying both gets both.

import Combine
import Foundation

// MARK: - A leaf level

/// Five collaborators, all read-only, none with a synthesizable default — so
/// the generated mock takes all five as initializer parameters. That is the
/// ergonomics a test sees for every leaf.
///
/// The level owns nothing, so its Component is generated whole: a `final class
/// TimelineComponent` with five forwarders and nothing hand-written.
///
/// sourcery: CreateMock, DuetComponent
public protocol TimelineDependency: AnyObject {
  var themeProvider: ThemeProviding { get }
  var memoryRepository: MemoryRepositoryProtocol { get }
  var userRepository: UserRepositoryProtocol { get }
  var analytics: AnalyticsTracking { get }
  var audioSessionConfigurer: AudioSessionConfiguring { get }
}

// MARK: - A subtree level that also owns

/// The parent forwards most of its surface and owns a member of its own. A
/// mock of it is the same shape either way: ownership is a fact about the
/// Component, not about the Dependency protocol.
///
/// `owns` is what makes that fact reach the generator: the emission becomes a
/// non-final `MainComponentBase`, because a generated type cannot carry a
/// hand-written `lazy var`.
///
/// sourcery: CreateMock, DuetComponent, owns
public protocol MainDependency: AnyObject {
  var themeProvider: ThemeProviding { get }
  var memoryRepository: MemoryRepositoryProtocol { get }
  var userRepository: UserRepositoryProtocol { get }
  var pushNotificationRepository: PushNotificationRepositoryProtocol { get }
  var analytics: AnalyticsTracking { get }
}

/// The hand-written half of an owning level — the only lines the level writes.
/// It holds what is scoped here; every forwarder is inherited from the
/// generated base, and the owned member reads them as if they were its own.
///
/// The child conformances hang here too: `TimelineDependency`'s five members are
/// a subset of `MainDependency`'s, so the parent satisfies the child's
/// Dependency with an empty extension, and the child's Component forwards to it.
final class MainComponent: MainComponentBase {
  lazy var feedAudioPlayer: FeedAudioPlayer = FeedAudioPlayer(
    memoryRepository: memoryRepository,
    analytics: analytics)
}

extension MainComponent: TimelineDependency {
  var audioSessionConfigurer: AudioSessionConfiguring { StubAudioSession() }
}

// MARK: - The degenerate root

/// The composition root consumes nothing from outside. The generated mock is
/// an empty class, which is the honest mock of an empty protocol.
///
/// sourcery: CreateMock
public protocol RootDependency: AnyObject {}

// MARK: - Composite protocols

/// Two narrow registration surfaces and the composite a caller reaches for.
/// The mock of the composite must carry the inherited requirements too.
///
/// sourcery: CreateMock
@MainActor
public protocol AppServicesAPNSHandlerRegistering {
  func registerAPNSNotificationsHandler(_ tag: String, priority: Int) -> AnyCancellable
}

/// sourcery: CreateMock
@MainActor
public protocol AppServicesURLHandlerRegistering {
  func registerURLHandler(_ tag: String, priority: Int) -> AnyCancellable
}

/// The Component of a composite must forward the inherited requirements too, and
/// its emitted name is derived from the whole protocol name when that name does
/// not end in `Dependency` — `AppServicesRegisteringComponent`.
///
/// sourcery: CreateMock, DuetComponent
@MainActor
public protocol AppServicesRegistering: AppServicesAPNSHandlerRegistering,
                                        AppServicesURLHandlerRegistering {
  func handlersDidRegister()
}

// MARK: - Optional existentials

/// The shape a `MemoryDetail` Builder takes in WikiMemory: a restored sheet
/// arrives as `(any DetailSheet)?`, and one of the closures takes it too.
///
/// The parser reports every one of these without its parentheses — `any
/// DetailSheet?` — which does not compile ("optional 'any' type must be written
/// '(any DetailSheet)?'"). Both templates emit types, so both are pinned here.
public protocol DetailSheet {}
public protocol DetailPolicy {}

/// sourcery: CreateMock, DuetComponent
public protocol DetailPresenting: AnyObject {
  /// Optional existential as a stored requirement.
  var restoredSheet: (any DetailSheet)? { get }

  /// Optional protocol composition.
  var policy: (any DetailSheet & DetailPolicy)? { get }

  /// Optional existential as a parameter, as the return type, and nested inside
  /// a closure parameter — the nested one survives a fix that only looks at the
  /// top-level type.
  func present(
    sheet: (any DetailSheet)?,
    onDismiss: @escaping ((any DetailSheet)?) -> Void
  ) -> (any DetailSheet)?

  /// A non-optional existential in an array, which must NOT gain parentheses.
  func presentAll(_ sheets: [any DetailSheet]) -> [any DetailSheet]
}
