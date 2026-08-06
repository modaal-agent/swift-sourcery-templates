// The composition shapes these templates have to mock: a `<X>Dependency`
// protocol per level, and the `<X>Buildable` that mounts it.
//
// Source: the WikiMemory reference app, where every composition level declares
// a Dependency protocol naming exactly what it consumes and a Component that
// forwards or owns each member. Generated mocks are what makes one protocol per
// level cheap enough to be the rule, so the shape is checked here.

import Combine
import Foundation

// MARK: - A leaf level

/// Five collaborators, all read-only, none with a synthesizable default — so
/// the generated mock takes all five as initializer parameters. That is the
/// ergonomics a test sees for every leaf.
///
/// sourcery: CreateMock
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
/// sourcery: CreateMock
public protocol MainDependency: AnyObject {
  var themeProvider: ThemeProviding { get }
  var memoryRepository: MemoryRepositoryProtocol { get }
  var userRepository: UserRepositoryProtocol { get }
  var pushNotificationRepository: PushNotificationRepositoryProtocol { get }
  var analytics: AnalyticsTracking { get }
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

/// sourcery: CreateMock
@MainActor
public protocol AppServicesRegistering: AppServicesAPNSHandlerRegistering,
                                        AppServicesURLHandlerRegistering {
  func handlersDidRegister()
}
