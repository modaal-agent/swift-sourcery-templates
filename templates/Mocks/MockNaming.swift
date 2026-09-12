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

    /// One parameter's contribution to an overload's long-form prefix (§2.2
    /// step 2): the capitalized argument label, or the capitalized parameter
    /// name when the parameter has no label.
    ///
    /// The label is what the caller writes, so `func end(atDocument document:)`
    /// gives `endAtDocument` rather than `endAtDocumentDocument`. Where label
    /// and name are the same word, or there is no label, this is the name —
    /// `func update(id:force:)` gives `updateIdForce` either way.
    static func overloadComponent(argumentLabel: String?, parameterName: String) -> String {
        return (argumentLabel ?? parameterName).withoutBackticks.uppercasedFirstLetter()
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

    // MARK: - Naming comments
    //
    // Three cases leave a prefix a reader cannot derive from the declaration in
    // front of them (`spec.md` §10.1): an overload's long form, the return-type
    // discriminator, and `/// sourcery: methodName`. 47 of the 152 methods in
    // the reference consumer are one of the three, in 10 of its 34 mock
    // classes. Each gets a comment carrying both spellings — the selector as
    // declared and the prefix its members take — above the witness and in its
    // class's index (D15(c)).
    //
    // The comment comes from the call that produces the name, so a comment that
    // disagrees with the member below it cannot be written (D16(a)), and
    // `Tests/Checks/run-checks.sh`'s naming-comment gate reads both back out of
    // the generated file (D16(b)).

    /// A method's prefix, and the comment recording it when it is not the
    /// declared name.
    struct MethodPrefix {
        let prefix: String
        /// `nil` when the prefix is the declared name, which is the case for
        /// most members.
        let comment: String?
    }

    /// The prefix a method's members carry, with that comment.
    ///
    /// - Parameters:
    ///   - selectorName: the requirement as declared — `end(at:)`. One of the
    ///     two spellings the comment carries, so a search for either finds it.
    ///   - callName: the method's declared name.
    ///   - longFormComponents: empty for the overload that keeps the plain
    ///     name; otherwise one component per parameter, from `overloadComponent`.
    ///   - returnTypeName: the return type, when the long form left two
    ///     overloads sharing a name and the discriminator is what separates
    ///     them; `nil` otherwise. The discriminator is derived from it here, so
    ///     the token in the name and the type in the comment are one input.
    ///   - annotatedName: the value of `/// sourcery: methodName`, which
    ///     replaces the derived prefix outright.
    static func methodPrefix(
        selectorName: String,
        callName: String,
        longFormComponents: [String] = [],
        returnTypeName: String? = nil,
        annotatedName: String? = nil
    ) -> MethodPrefix {
        let declaredName = callName.withoutBackticks
        let prefix: String
        let cause: String
        if let annotatedName = annotatedName {
            prefix = annotatedName
            cause = "`/// sourcery: \(AnnotationRegistry.methodName.name) = \"\(annotatedName)\"`"
        } else {
            prefix = methodPrefix(
                callName: callName,
                longFormComponents: longFormComponents,
                returnTypeDiscriminator: returnTypeName.map { returnTypeDiscriminator(forTypeNamed: $0) })
            cause = returnTypeName.map { "overload of `\(declaredName)` returning `\($0)`" }
                ?? "overload of `\(declaredName)`, argument labels appended"
        }
        // What decides whether a comment is written is the prefix against the
        // declared name, not which branch produced it: a method with no
        // parameters put into long form by its overload group derives the plain
        // name anyway, and an annotation may repeat the declared name.
        guard prefix != declaredName else {
            return MethodPrefix(prefix: prefix, comment: nil)
        }
        // `selectorName` is `refresh` for a method that takes nothing and
        // `end(at:)` for one that does. The comment shows the parentheses
        // either way, so the spelling it carries is the declaration's.
        let selector = selectorName.contains("(") ? selectorName : "\(selectorName)()"
        return MethodPrefix(
            prefix: prefix,
            comment: "`\(selector)` members are named `\(prefix)*` — \(cause)")
    }

    /// The comment as it is emitted above the witness, inside the class.
    static func namingCommentLine(_ comment: String) -> String { return "// \(comment)" }

    /// The same comment as it is emitted in its class's index. The indent is
    /// what separates an index entry from the class header sharing its column,
    /// for a reader and for the gate alike.
    static func namingIndexLine(_ comment: String) -> String { return "//   \(comment)" }

    /// Introduces the index, and is emitted only for a class that has one.
    static let namingIndexHeaderLine = "// Not named after their declaration:"

    /// The rule, stated once at the top of a generated file (D14(a)).
    static var fileNamingHeaderLines: [String] {
        return [
            "// Mock member names are the requirement's declared name plus a suffix: `func load()` gives",
            "// `loadCallCount`, `loadArgs` and `loadHandler`; `var name` gives `nameGetCount`, `nameSetCount`,",
            "// `nameGetHandler` and the store `_name`. Where a prefix is not the declared name — an overload,",
            "// a return-type discriminator, `sourcery: \(AnnotationRegistry.methodName.name)` — a comment carrying both spellings",
            "// sits above the witness and in the index under that class's `// MARK:` line.",
        ]
    }

    /// The rule again, under every class's `MARK:` line (D14(b)). A generated
    /// file is read in slices — the consumer's is 2934 lines — and the file
    /// header is not in the slice. The same two lines for every class, with
    /// nothing interpolated from the protocol.
    static var classNamingHeaderLines: [String] {
        return [
            "// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,",
            "// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.",
        ]
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

    /// The stored value behind a property requirement's accessors (§2.5). A test
    /// seeds and reads it without moving a counter, and the generated
    /// initializer assigns it.
    ///
    /// The underscore is what the generator already uses for a name it owns —
    /// `__<name>Handler` is the handler local inside every generated method — and
    /// a protocol that declares `_draft` itself is caught by
    /// `checkForCollisions` rather than emitting a file that does not compile
    /// (D9).
    static func store(_ prefix: String) -> String { return "_\(prefix)" }

    // MARK: - Stream members

    static func subject(_ prefix: String) -> String { return "\(prefix)Subject" }
    static func eventCallCount(_ prefix: String) -> String { return "\(prefix)EventCallCount" }
    static func eventHandler(_ prefix: String) -> String { return "\(prefix)EventHandler" }
    static func events(_ prefix: String) -> String { return "\(prefix)Events" }

    static func subscribeCount(_ prefix: String) -> String { return "\(prefix)SubscribeCount" }
    static func subscribeCancelCount(_ prefix: String) -> String { return "\(prefix)SubscribeCancelCount" }
    static func outputCount(_ prefix: String) -> String { return "\(prefix)OutputCount" }
    static func outputs(_ prefix: String) -> String { return "\(prefix)Outputs" }
    static func outputHandler(_ prefix: String) -> String { return "\(prefix)OutputHandler" }
    static func completionCount(_ prefix: String) -> String { return "\(prefix)CompletionCount" }

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
    // The text a generated member traps with, in one wording for a method and a
    // property alike (§2.4). The property form read
    // `` `<var>GetHandler` must be set! `` until P4 — three words and a pair of
    // backticks away from the method's, because each string was written where
    // its own member was emitted. `kotlin-ksp-mocks` matches this text byte for
    // byte.

    static func handlerExpectedMessage(handlerName: String) -> String {
        return "\(handlerName) expected to be set."
    }

    static func getHandlerExpectedMessage(prefix: String) -> String {
        return handlerExpectedMessage(handlerName: getHandler(prefix))
    }

    // MARK: - Collisions
    //
    // Nothing checked a generated property name before this. `MockMethod.from`
    // guarded duplicate *method* prefixes and `MockVar.from` uniqued the
    // requirements by name and no further, so a protocol declaring both `draft`
    // and `draftSetCount` emitted `var draftSetCount` twice and the generated
    // file did not compile, with nothing from the template saying why
    // (`spec.md` D9). The check below reads back what the class declares.

    /// The name a generated member declaration declares, or `nil` when the line
    /// declares no property.
    ///
    /// Only `var` and `let` are read. Two `func`s may legitimately share a base
    /// name — they are the protocol's own overloads, and Swift allows them —
    /// while two properties of one class may not, and the bookkeeping members
    /// are all properties.
    static func declaredPropertyName(inDeclaration line: String) -> String? {
        var remainder = Substring(line)
        var strippedModifier = true
        while strippedModifier {
            strippedModifier = false
            for modifier in declarationModifiers where remainder.hasPrefix(modifier) {
                remainder = remainder.dropFirst(modifier.count)
                strippedModifier = true
            }
        }
        guard remainder.hasPrefix("var ") || remainder.hasPrefix("let ") else { return nil }
        let name = remainder.dropFirst(4).prefix { $0 != ":" && $0 != " " && $0 != "=" }
        return name.isEmpty ? nil : String(name)
    }

    private static let declarationModifiers = ["nonisolated(unsafe) ", "nonisolated ", "lazy "]

    /// Fails generation when one mock class declares the same property twice.
    ///
    /// - Parameters:
    ///   - lines: the class's member declarations, in emission order.
    ///   - typeName: the mocked protocol, for the message.
    static func checkForCollisions(amongMemberDeclarations lines: [String], typeName: String) throws {
        var seen = Set<String>()
        for line in lines {
            guard let name = declaredPropertyName(inDeclaration: line) else { continue }
            guard !seen.contains(name) else {
                throw MockError.collidingMemberNames(typeName: typeName, memberName: name)
            }
            seen.insert(name)
        }
    }
}

private extension String {
    /// Backticks escape a keyword at the declaration and are not part of the
    /// name. They are the whole of §2.1's transform.
    var withoutBackticks: String {
        return replacingOccurrences(of: "`", with: "")
    }
}
