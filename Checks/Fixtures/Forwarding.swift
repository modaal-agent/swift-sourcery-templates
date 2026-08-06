// Requirement shapes a Component has to forward, beyond the plain read-only
// `var` that most of a Dependency protocol is made of.
//
// Forwarding is not mocking: a mock replaces a requirement's behaviour, a
// Component passes it through unchanged. So a construct the mock template
// cannot express may still be forwardable, and two of the protocols here are
// annotated `DuetComponent` alone for that reason — each says which construct
// puts it there.

import Combine
import Foundation

// MARK: - Isolation, mutation, effects

/// A level whose surface mixes everything the isolation rules touch: a settable
/// requirement, a nonisolated port on a `@MainActor` protocol (doc-15 §1.4
/// constraint 4 — the node declares it, the app adapts), and an `async throws`
/// method.
///
/// The nonisolated members are why the generated Component declares its storage
/// `nonisolated(unsafe)`: a nonisolated forwarder cannot read a main-actor
/// isolated stored property. That is an unchecked assertion, and it is the same
/// one the mock template makes about its call counters.
///
/// sourcery: CreateMock, DuetComponent
@MainActor
public protocol CaptureDependency: AnyObject {
  /// Read *and* written by the level, so the forwarder needs both accessors.
  var draft: String { get set }

  var memoryRepository: MemoryRepositoryProtocol { get }
  var analytics: AnalyticsTracking { get }

  nonisolated var installationId: String { get }
  nonisolated func ping()

  func stage(_ fileName: String, retries: Int) async throws -> URL
  func discard(reason: String)
}

// MARK: - Parameter shapes

/// Parameter forms whose *declaration* has to survive into the forwarder or the
/// conformance breaks, and whose *call* has to be spelled the way the
/// declaration labels it.
///
/// `DuetComponent` only: the generic method needs the mock template's
/// `annotatedGenericTypes` annotation to produce a usable double, and this
/// fixture is about forwarding rather than about that.
///
/// sourcery: DuetComponent
public protocol RegistrationDependency: AnyObject {
  var themeProvider: ThemeProviding { get }

  /// No argument label: the call site must not invent one.
  func submit(_ code: String)

  /// A label that differs from the parameter name.
  func retry(after delay: TimeInterval, attempts: Int)

  /// `inout`: the declaration keeps it, the call site passes `&`.
  func accumulate(into total: inout Int)

  /// Generic: the declaration carries the clause, the call site must not.
  func encode<T: Encodable>(_ value: T) throws -> Data

  /// `@escaping @Sendable` — both attributes are part of the parameter's type,
  /// and dropping either changes what a caller may pass.
  func schedule(fileName: String, completion: @escaping @Sendable (Bool) -> Void)

  /// `rethrows` forwards as `rethrows`, called with `try`.
  func withRetries(_ body: () throws -> Void) rethrows
}

/// Satisfies `RegistrationDependency` so the generated Component has a parent to
/// forward to. Hand-written because the protocol is not mocked.
final class StubRegistrationDependency: RegistrationDependency {
  let themeProvider: ThemeProviding = StubThemeProvider(accentName: "registration")

  private(set) var submitted: [String] = []
  private(set) var retries: [(TimeInterval, Int)] = []
  private(set) var scheduled: [String] = []

  func submit(_ code: String) { submitted.append(code) }
  func retry(after delay: TimeInterval, attempts: Int) { retries.append((delay, attempts)) }
  func accumulate(into total: inout Int) { total += 1 }
  func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

  func schedule(fileName: String, completion: @escaping @Sendable (Bool) -> Void) {
    scheduled.append(fileName)
    completion(true)
  }

  func withRetries(_ body: () throws -> Void) rethrows { try body() }
}

// MARK: - Effectful property requirements

/// A requirement that suspends and throws on *read*. Forwarding it is a
/// pass-through; mocking it is not, so the mock template does not support it and
/// this protocol carries `DuetComponent` alone.
///
/// sourcery: DuetComponent
public protocol ProfileDependency: AnyObject {
  var currentUser: UserSummary { get async throws }
  var cachedUser: UserSummary? { get }
}

/// Satisfies `ProfileDependency` so the generated Component has a parent.
final class StubProfileDependency: ProfileDependency {
  var currentUser: UserSummary {
    get async throws { UserSummary(uid: "u1", displayName: "Alice") }
  }

  var cachedUser: UserSummary? { nil }
}

// MARK: - Naming and access overrides

/// The emitted type is internal even though the protocol is public: a
/// composition Component is consumed by its own module's builders, and widening
/// a module's API surface as a side effect of generating boilerplate is not a
/// decision a template should make. `componentAccess` is the opt-in.
///
/// `componentName` covers the level whose Component is not named after its
/// protocol — here the protocol is `OnboardingFlowDependency` and the Component
/// the app already calls `OnboardingComponent`. It is the emitted type's whole
/// name, not a stem.
///
/// sourcery: DuetComponent, componentName = "OnboardingComponent", componentAccess = "public"
public protocol OnboardingFlowDependency: AnyObject {
  var themeProvider: ThemeProviding { get }
}
