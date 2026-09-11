// What a property requirement generates, shape by shape.
//
// Every branch of `MockVar.mockImpl` is declared here once: a read-only
// requirement whose type has a synthesizable default, a mutable one, one with no
// default that the initializer seeds, `/// sourcery: const`, and
// `/// sourcery: handler` in both its read-only and its mutable form.
//
// The `handler` pair is what puts the property trap string in the snapshot.
// Before `specs/004-mock-member-naming/spec.md` §2.4 nothing under Tests/ carried
// that annotation, so the wording that diverged from the method's was visible in
// no generated file this repository holds.

import Foundation

/// sourcery: ProtocolMock
public protocol PropertyShaped: AnyObject {
  /// Read-only, synthesizable default: a `var` a test re-seeds.
  var identifier: String { get }

  /// Mutable, synthesizable default.
  var draft: String { get set }

  /// No synthesizable default: an initializer parameter.
  var themeProvider: ThemeProviding { get }

  /// The value is fixed at construction.
  ///
  /// sourcery: const
  var buildNumber: Int { get }

  /// Read-only, supplied by the test rather than stored. A read with no handler
  /// set traps.
  ///
  /// sourcery: handler
  var snapshot: [String: Int] { get }

  /// The same, mutable: the getter traps and the setter counts.
  ///
  /// sourcery: handler
  var cursor: Int { get set }
}
