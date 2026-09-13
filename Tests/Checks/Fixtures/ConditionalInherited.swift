// The base of `ConditionalInheriting` (Conditional.swift), in a file of its own:
// a member inherited under a condition reaches the refining protocol's mock
// from another file (spec 006 §8.5). No selector, so no mock of its own.

public protocol ConditionalInheritedBase: AnyObject {
  func refresh()
  #if FIXTURE_CONDITION_B
  /// sourcery: if = "FIXTURE_CONDITION_B"
  func receive(_ token: ConditionBToken)
  #endif
}
