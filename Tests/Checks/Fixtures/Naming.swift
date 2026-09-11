// The naming rule itself: what prefix a declared name produces.
//
// `specs/004-mock-member-naming/spec.md` §2.1 states it — the declared name with
// backticks removed, and nothing else. Before that rule, methods went through a
// transform properties did not: `perform1_0` became `perform10`, `load_data` and
// `loadData` became the same name, and an all-uppercase name crashed generation.
// Each protocol below is one of those cases, and the snapshot is where the
// answer is visible.

import Foundation

/// An underscore in a method name beside an underscore in a property name. Under
/// the old transform the first became `perform10` and the second stayed
/// `setting4_2`, which is the two-transforms-in-one-class case (§1.1).
///
/// sourcery: ProtocolMock
public protocol NamingUnderscores: AnyObject {
  var setting4_2: Int { get set }
  func perform1_0()
  func perform2_0(value: Int)
}

/// Two names the old transform mapped onto one. `load_data` and `loadData` both
/// produced `loadData`, and generation failed with "not all duplicates
/// resolved"; they are distinct declarations and now carry distinct members.
///
/// sourcery: ProtocolMock
public protocol NamingManyToOne: AnyObject {
  func load_data()
  func loadData()
}

/// An all-uppercase name. `lowerFirstWord` indexed past the end of the string on
/// this input and crashed the run (§1.2); the prefix is now the name.
///
/// sourcery: ProtocolMock
public protocol NamingUppercase: AnyObject {
  func ID() -> String
  func URLSession() -> String
}

/// Keyword-named requirements. The backticks escape the keyword where the member
/// is declared and are not part of the name, so the witness keeps them and the
/// bookkeeping members drop them.
///
/// sourcery: ProtocolMock
public protocol NamingKeywords: AnyObject {
  var `default`: Int { get set }
  func `do`()
  func `repeat`(times: Int)
}
