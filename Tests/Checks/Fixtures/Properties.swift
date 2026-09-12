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

/// Effectful property requirements. `var x: T { get async throws }` is parsed —
/// `SourceryRuntime.Variable.isAsync` and `Variable.throws` — and the mock
/// template ignored it until §2.6, emitting a plain stored property that did not
/// satisfy the requirement. The only effectful requirement anywhere under
/// `Tests/` before this file is `Forwarding.swift`'s, which is `DuetComponent`
/// alone, so the mock template had never seen one.
///
/// Swift has no effectful setter, so each of these is get-only and none carries a
/// `<var>SetCount`. A test seeds `_<var>`.
///
/// sourcery: ProtocolMock
public protocol PropertyEffectful: AnyObject {
  var config: String { get async throws }
  var token: String { get async }
  var secret: String { get throws }
  var plain: String { get }

  /// No synthesizable default, so the initializer seeds the store and the
  /// accessor still suspends.
  var loader: ThemeProviding { get async }
}
