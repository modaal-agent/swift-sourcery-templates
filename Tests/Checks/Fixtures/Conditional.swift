// Declarations generated inside a condition (spec 006 §8.5).
//
// Sourcery reads every clause of an `#if` and records no condition, so each
// conditional declaration here also carries `sourcery: if` naming the same
// condition. The fast lane typechecks the fixtures with no flag, with
// `-D FIXTURE_CONDITION_A` and with `-D FIXTURE_CONDITION_B`. A member under a
// flag names a type declared only under that flag, so a mock that emits the
// member outside its condition, or under the wrong one, does not compile.

import Combine
import Foundation

#if FIXTURE_CONDITION_A
public struct ConditionAToken: Equatable {
  public init() {}
}
#endif

#if FIXTURE_CONDITION_B
public struct ConditionBToken: Equatable {
  public init() {}
}
#endif

/// One `if` on a member. `ticks` carries `canImport(Combine)`, which guards the
/// configured `import Combine` of the generated file (§9.4).
/// sourcery: ProtocolMock, DuetComponent
public protocol ConditionalMember: AnyObject {
  func load() -> Int
  #if FIXTURE_CONDITION_A
  /// sourcery: if = "FIXTURE_CONDITION_A"
  func adopt(_ token: ConditionAToken)
  #endif
  #if canImport(Combine)
  /// sourcery: if = "canImport(Combine)"
  var ticks: AnyPublisher<Int, Never> { get }
  #endif
}

/// Two `if` lines on one member, joined with `&&`.
/// sourcery: ProtocolMock, DuetComponent
public protocol ConditionalStacked: AnyObject {
  func reset()
  #if FIXTURE_CONDITION_A
  #if FIXTURE_CONDITION_B
  /// sourcery: if = "FIXTURE_CONDITION_A"
  /// sourcery: if = "FIXTURE_CONDITION_B"
  func pair(_ first: ConditionAToken, _ second: ConditionBToken)
  #endif
  #endif
}

/// `sourcery:begin` / `sourcery:end` around two members.
/// sourcery: ProtocolMock, DuetComponent
public protocol ConditionalBlock: AnyObject {
  func plain()
  #if FIXTURE_CONDITION_B
  // sourcery:begin: if = "FIXTURE_CONDITION_B"
  var token: ConditionBToken? { get }
  func accept(_ token: ConditionBToken)
  // sourcery:end
  #endif
}

#if FIXTURE_CONDITION_A
/// A whole protocol inside a condition. Its property has no default value, so
/// the mock's initializer takes it, inside the same `#if`.
/// sourcery: ProtocolMock, DuetComponent
/// sourcery: if = "FIXTURE_CONDITION_A"
public protocol ConditionalWhole: AnyObject {
  var token: ConditionAToken { get }
  func adopt(_ token: ConditionAToken)
}
#endif

/// `receive(_:)` is inherited from `ConditionalInheritedBase`, declared in
/// ConditionalInherited.swift, and carries the `if` of its own declaration.
/// sourcery: ProtocolMock, DuetComponent
public protocol ConditionalInheriting: ConditionalInheritedBase {
  func own()
}

/// One declaration in both clauses of an `#if`. Sourcery folds the two into one
/// member, whose condition joins both with `||`.
/// sourcery: ProtocolMock, DuetComponent
public protocol ConditionalMerged: AnyObject {
  #if FIXTURE_CONDITION_A
  /// sourcery: if = "FIXTURE_CONDITION_A"
  func render() -> Int
  #else
  /// sourcery: if = "!FIXTURE_CONDITION_A"
  func render() -> Int
  #endif
}

/// One property name with a different type in each clause. Both are generated,
/// each inside its own condition, with the same member names.
/// sourcery: ProtocolMock, DuetComponent
public protocol ConditionalTwoTypes: AnyObject {
  #if FIXTURE_CONDITION_B
  /// sourcery: if = "FIXTURE_CONDITION_B"
  var mode: ConditionBToken? { get }
  #else
  /// sourcery: if = "!FIXTURE_CONDITION_B"
  var mode: Int { get }
  #endif
}
