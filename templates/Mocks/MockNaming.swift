import Foundation
import SourceryRuntime

/// The one place a generated mock member's name is built.
///
/// `MockMethod`, `MockVar`, `MockGenerator` and `SourceryRuntimeExtensions` ask
/// for a name here instead of interpolating a suffix where the member is
/// emitted. That is what keeps the vocabulary one vocabulary: the method trap
/// string and the property trap string came to differ by three words and a pair
/// of backticks because each was written at its own site
/// (`specs/004-mock-member-naming/spec.md` §1.8).
///
/// A member name is a **prefix**, derived from the declaration, and a
/// **suffix** naming what the member records. `spec.md` §2 states the rule;
/// `AGENTS.md` §"State a rule once" names this file as its home.
enum MockNaming {

    // MARK: - Prefixes

    /// The prefix every generated member of a method carries: the declared name
    /// with backticks removed, and nothing else — no case change, no underscore
    /// removal, no first-word lowercasing (`spec.md` §2.1). `func perform1_0()`
    /// gives `perform1_0`, `func ID()` gives `ID`, `` func `do`() `` gives `do`.
    ///
    /// - Parameters:
    ///   - callName: the method's declared name.
    ///   - longFormComponents: empty for the overload that keeps the plain name;
    ///     otherwise one component per parameter, from `overloadComponent`.
    ///   - returnTypeDiscriminator: the last-resort overload disambiguator, or
    ///     `nil`.
    static func methodPrefix(
        callName: String,
        longFormComponents: [String] = [],
        returnTypeDiscriminator: String? = nil
    ) -> String {
        var components = [callName.withoutBackticks]
        components += longFormComponents
        if let returnTypeDiscriminator = returnTypeDiscriminator {
            components += [returnTypeDiscriminator]
        }
        return components.joined()
    }

    /// One parameter's contribution to an overload's long-form prefix.
    static func overloadComponent(argumentLabel: String?, parameterName: String) -> String {
        let label: String
        if let argumentLabel = argumentLabel, argumentLabel != parameterName {
            label = argumentLabel.uppercasedFirstLetter()
        } else {
            label = ""
        }
        return "\(label)\(parameterName.uppercasedFirstLetter())"
    }

    /// The key overloads are grouped under before the disambiguation chain runs.
    /// Two declarations share a group when they share this key.
    static func overloadGroupKey(shortName: String) -> String {
        return shortName.withoutBackticks
    }

    /// The prefix every generated member of a property carries, under §2.1's
    /// one rule: `var setting4_2: Int` gives `setting4_2`. A keyword-named
    /// requirement keeps its backticks where it is *declared* — `` var `default`:
    /// Int `` is the witness — and drops them here, because `` `default`GetCount ``
    /// is not an identifier.
    static func variablePrefix(name: String) -> String {
        return name.withoutBackticks
    }

    /// Suffix derived from a method's return type, used to disambiguate
    /// overloads that share the same name *and* the same parameter list but
    /// differ only by return type (e.g., a refining protocol overriding
    /// `func data() -> [String: Any]?` with `func data() -> [String: Any]`).
    /// Such overloads cannot be distinguished by parameter labels alone.
    ///
    /// Examples:
    /// - `[String: Any]?` → `StringAnyOptional`
    /// - `[String: Any]`  → `StringAny`
    /// - `String?`        → `StringOptional`
    /// - `String`         → `String`
    static func returnTypeDiscriminator(forTypeNamed typeName: String) -> String {
        var sanitized = typeName
            .replacingOccurrences(of: "?", with: "_Optional")
            .replacingOccurrences(of: "!", with: "_Forced")
            .replacingOccurrences(of: "[", with: "_")
            .replacingOccurrences(of: "]", with: "_")
            .replacingOccurrences(of: "(", with: "_")
            .replacingOccurrences(of: ")", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ",", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "&", with: "_")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: " ", with: "_")
        while sanitized.contains("__") {
            sanitized = sanitized.replacingOccurrences(of: "__", with: "_")
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        // Force snake_case → CamelCase. `camelCased()` splits on `_`.
        return sanitized.camelCased().uppercasedFirstLetter()
    }

    // MARK: - Method members

    static func callCount(_ prefix: String) -> String { return "\(prefix)CallCount" }
    static func args(_ prefix: String) -> String { return "\(prefix)Args" }
    static func handler(_ prefix: String) -> String { return "\(prefix)Handler" }

    /// The local a generated method binds its handler to before calling it. The
    /// underscores are what keep it from shadowing a parameter of the same name.
    static func handlerLocal(_ handlerName: String) -> String { return "__\(handlerName)" }

    // MARK: - Property members

    static func getCount(_ prefix: String) -> String { return "\(prefix)GetCount" }
    static func getHandler(_ prefix: String) -> String { return "\(prefix)GetHandler" }
    static func setCount(_ prefix: String) -> String { return "\(prefix)SetCount" }

    // MARK: - Stream members

    static func subject(_ prefix: String) -> String { return "\(prefix)Subject" }
    static func eventCallCount(_ prefix: String) -> String { return "\(prefix)EventCallCount" }
    static func eventHandler(_ prefix: String) -> String { return "\(prefix)EventHandler" }

    // MARK: - Returned-token members
    //
    // The suffix is the name of the call the returned token exposes:
    // `AnyCancellable.cancel()` gives `Cancel*`, RxSwift's `Disposable.dispose()`
    // gives `Dispose*` (`spec.md` D4).

    static func cancelCallCount(_ prefix: String) -> String { return "\(prefix)CancelCallCount" }
    static func cancelHandler(_ prefix: String) -> String { return "\(prefix)CancelHandler" }
    static func disposeCallCount(_ prefix: String) -> String { return "\(prefix)DisposeCallCount" }
    static func disposeHandler(_ prefix: String) -> String { return "\(prefix)DisposeHandler" }

    // MARK: - Diagnostics
    //
    // The text a generated member traps with. `kotlin-ksp-mocks` matches the
    // method form byte for byte.

    static func handlerExpectedMessage(handlerName: String) -> String {
        return "\(handlerName) expected to be set."
    }

    static func getHandlerExpectedMessage(prefix: String) -> String {
        return "`\(getHandler(prefix))` must be set!"
    }
}

private extension String {
    /// Backticks escape a keyword at the declaration and are not part of the
    /// name. They are the whole of §2.1's transform.
    var withoutBackticks: String {
        return replacingOccurrences(of: "`", with: "")
    }
}
