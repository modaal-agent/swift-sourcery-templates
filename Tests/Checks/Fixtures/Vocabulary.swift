// The annotation vocabulary itself: which spelling selects which template.
//
// Every other fixture writes `CreateMock`, which is the spelling that shipped
// and is now an alias. These three protocols cover what the alias table claims:
// the canonical selector, the selector that had no coverage at all before, and
// the legacy pair a consumer's source still carries.
//
// Names are matched exactly, including case. A misspelling is checked by the
// near-miss section of `run-checks.sh` and by `PluginFixtureRed/NearMiss`, not
// here — a fixture that fails generation would fail it for every other fixture
// in the same run.

import Foundation

/// The canonical selector. `CreateMock` elsewhere in this directory reaches the
/// same record through an alias, and both produce the same class.
///
/// sourcery: ProtocolMock
public protocol VocabularyCanonical: AnyObject {
  var identifier: String { get }
  func refresh()
}

/// `ObjcProtocolMock` on its own. Before it was a selector, `ObjcProtocol`
/// without `CreateMock` beside it generated nothing at all, and nothing under
/// `Tests/` or `Tests/Examples/` ever wrote it — this is its first coverage.
///
/// sourcery: ObjcProtocolMock
public protocol VocabularyObjc: AnyObject {
  func reload()
}

/// The pair every existing consumer writes. `CreateMock` matches the mock
/// selector through its alias and `ObjcProtocol` matches the `NSObject` one
/// through its own, so the two annotations together land on exactly the class
/// the one above does.
///
/// sourcery: CreateMock, ObjcProtocol
public protocol VocabularyLegacyObjc: AnyObject {
  func flush()
}
