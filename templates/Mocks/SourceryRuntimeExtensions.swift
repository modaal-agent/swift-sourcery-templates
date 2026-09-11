import Foundation
import SourceryRuntime

// MARK: - Concurrency

extension SourceryRuntime.`Type` {

    /// The global actor the protocol is isolated to, without the leading `@`,
    /// or `nil` when the protocol is not isolated.
    ///
    /// `@MainActor` is recognized by name. Any other attribute whose name ends
    /// in `Actor` is treated as a custom global actor, which covers the
    /// conventional naming. When a global actor is named otherwise, declare it
    /// explicitly with `/// sourcery: globalActor = "MyIsolation"`; the
    /// annotation wins over the attribute.
    var globalActorAttributeName: String? {
        if let annotated = annotations(for: AnnotationRegistry.globalActor).first, !annotated.isEmpty {
            return annotated.hasPrefix("@") ? String(annotated.dropFirst()) : annotated
        }
        let actorAttributes = attributes.keys
            .filter { $0 == "MainActor" || $0.hasSuffix("Actor") }
            .sorted()
        return actorAttributes.first
    }

    /// `true` when the protocol refines `Sendable`, directly or through a
    /// protocol Sourcery has resolved.
    ///
    /// A mock of such a protocol cannot be a checked `Sendable`: its call
    /// counters are mutable stored properties. `@unchecked` is the accurate
    /// statement for a test double, and it is what keeps the generated file
    /// compiling in the Swift 6 language mode.
    var requiresUncheckedSendable: Bool {
        if isAnnotated(AnnotationRegistry.uncheckedSendable) { return true }
        if inheritedTypes.contains("Sendable") { return true }
        return based.keys.contains("Sendable")
    }
}

extension SourceryRuntime.`Type` {
    /// Members of an isolated mock that satisfy a `nonisolated` requirement
    /// need the modifier restated, and their backing storage needs
    /// `nonisolated(unsafe)`. On a mock with no global actor the modifiers are
    /// redundant, so they are emitted only where they are load-bearing.
    var emitsNonisolatedMembers: Bool {
        return globalActorAttributeName != nil
    }
}

extension SourceryRuntime.Method {
    var isDeclaredNonisolated: Bool {
        return modifiers.contains { $0.name == "nonisolated" }
    }
}

extension SourceryRuntime.Variable {
    var isDeclaredNonisolated: Bool {
        return modifiers.contains { $0.name == "nonisolated" }
    }
}

// MARK: - Combine subjects

/// Which subject backs a generated `AnyPublisher` member.
enum SubjectKind {
    case automatic
    case currentValue
    case passthrough
}

// MARK: - Annotated member shapes

// What a `/// sourcery:` option means for one mocked member. The verbs come
// from `Annotations/AnnotationRegistry.swift`; what they do to a mock is this
// file's subject, which is why these live here and not beside the registry.

extension SourceryRuntime.Annotated {
    // `get`-only variable requirements in protocols are considered mutable and are mocked using `var` declarations by default.
    // To generate a `let` declaration, annotate with `sourcery: const`.
    var isAnnotatedConst: Bool {
        return isAnnotated(AnnotationRegistry.const)
    }

    // For a 'get'-only variable requirement in the protocol, determine if it should be included in the mock class' initializer list.
    var isAnnotatedInit: Bool {
        precondition(!isAnnotatedInitInternal || !isAnnotatedHandlerInternal, "`isAnnotatedInit` is mutually exclusive with `isAnnotatedHandler`")
        return isAnnotatedInitInternal
    }
    private var isAnnotatedInitInternal: Bool {
        return isAnnotated(AnnotationRegistry.initVariable)
    }

    // Suppresses the `<method>Args` array on a mocked method, or on every method
    // of a protocol when it is declared on the type.
    //
    // A recorded argument lives as long as the mock does. When the argument is
    // the object a churn or leak spec asserts the deallocation of, that retain
    // reads as a leak in the code under test, and this is the opt-out. Call
    // counts and the handler are unaffected.
    var isAnnotatedSkipArgumentRecording: Bool {
        return isAnnotated(AnnotationRegistry.skipArgumentRecording)
    }

    // For a `get`-only variable requirement in the protocol,
    var isAnnotatedHandler: Bool {
        precondition(!isAnnotatedHandlerInternal || !isAnnotatedInitInternal, "`isAnnotatedHandler` is mutually exclusive with `isAnnotatedInit`")
        return isAnnotatedHandlerInternal
    }
    private var isAnnotatedHandlerInternal: Bool {
        return isAnnotated(AnnotationRegistry.handler)
    }
}

extension SourceryRuntime.Annotated {
    /// `/// sourcery: subject = "CurrentValue"` / `"Passthrough"` on the member.
    /// Also accepts the full type names.
    var requestedSubjectKind: SubjectKind {
        switch annotations(for: AnnotationRegistry.subject).first?.lowercased() {
        case "currentvalue", "currentvaluesubject": return .currentValue
        case "passthrough", "passthroughsubject": return .passthrough
        default: return .automatic
        }
    }
}

extension SourceryRuntime.TypeName {

    var hasDefaultValue: Bool {
        return (try? defaultValue()) != nil
    }

    func defaultValue() throws -> String {
        if isOptional { return "nil" }
        if isVoid { return "()" }
        if isArray { return "[]" }
        if isDictionary { return "[:]" }
        if isTuple, let tuple = tuple {
            let joined = try tuple.elements.map { try $0.typeName.defaultValue() }.joined(separator: ", ")
            return "(\(joined))"
        }

        switch unwrappedTypeName {
        case "String": return "\"\""
        case "Bool": return "false"
        case "Int", "Int32", "Int64", "UInt", "UInt32", "UInt64": return "0"
        case "Float", "Double": return "0.0"
        case "NSTimeInterval", "TimeInterval": return "0.0"
        case "CGFloat": return "CGFloat(0)"
        case "CGPoint", "NSPoint": return "CGPoint.zero"
        case "CGSize", "NSSize": return "CGSize.zero"
        case "CGRect", "NSRect": return "CGRect.zero"
        default:
            break
        }

        if let generic = generic {
            switch generic.name {
            case "Set": return "\(generic.name)()"
            default:
                break
            }
        }

        throw MockError.noDefaultValue(typeName: self)
    }

    /// The type as this template must WRITE it — `name` with the parentheses
    /// the parser drops around an optional existential put back.
    ///
    /// Every site that emits a type reads this or `mockTypeName`; neither
    /// `name` nor `asSource` is safe to emit directly. See
    /// `parenthesizingOptionalExistentials`.
    var declaredName: String {
        Self.parenthesizingOptionalExistentials(name)
    }

    var mockTypeName: String {
        Self.parenthesizingOptionalExistentials(unparenthesizedMockTypeName)
    }

    private var unparenthesizedMockTypeName: String {
        if isVoid {
            return "()"
        }

        if isTuple, let tuple {
            return tuple.name + (isOptional ? "?" : "")
        }

        if isArray, let array {
            return "[\(array.elementTypeName.mockTypeName)]" + (isOptional ? "?" : "")
        }

        if isDictionary, let dictionary {
            return "[\(dictionary.keyTypeName.mockTypeName) : \(dictionary.valueTypeName.mockTypeName)]" + (isOptional ? "?" : "")
        }

        return actualTypeName?.mockTypeName ?? name
    }

    /// Restores the parentheses the parser drops around an optional existential.
    ///
    /// `(any Sheet)?` in source comes back as `any Sheet?` from `name` AND from
    /// `asSource`, and `any Sheet?` is not valid Swift — the compiler answers
    /// "optional 'any' type must be written '(any Sheet)?'". The loss is the
    /// same for `some`, for a protocol composition (`(any A & B)?`), and
    /// wherever the type appears: `((any Sheet)?) -> Void` comes back as
    /// `(any Sheet?) -> Void`, so a fix that only inspects `isOptional` at the
    /// top level leaves the closure case broken. This works on the rendered
    /// string instead, which is the one form every case shares.
    ///
    /// Each pass wraps the FIRST occurrence that needs it and returns; the loop
    /// repeats until a pass finds none, which handles nesting without index
    /// bookkeeping and makes the function idempotent — an already-parenthesised
    /// `(any Sheet)?` ends its scan on `)`, not on `?`, so it is not re-wrapped.
    static func parenthesizingOptionalExistentials(_ source: String) -> String {
        var result = source
        while let wrapped = wrappingFirstOptionalExistential(in: result) {
            result = wrapped
        }
        return result
    }

    private static func wrappingFirstOptionalExistential(in source: String) -> String? {
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            guard isTokenStart(characters, at: index),
                  let keywordEnd = existentialKeywordEnd(characters, at: index) else {
                index += 1
                continue
            }
            let end = existentialEnd(characters, from: keywordEnd)
            var last = end - 1
            while last >= keywordEnd, characters[last] == " " { last -= 1 }
            if last >= keywordEnd, characters[last] == "?" || characters[last] == "!" {
                var wrapped = characters
                wrapped.insert(")", at: last)
                wrapped.insert("(", at: index)
                return String(wrapped)
            }
            index = keywordEnd
        }
        return nil
    }

    /// `any`/`some` only introduce an existential at the start of a token —
    /// `Company<T>` must not match on the `any` inside it.
    private static func isTokenStart(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return !(previous.isLetter || previous.isNumber || previous == "_")
    }

    private static func existentialKeywordEnd(_ characters: [Character], at index: Int) -> Int? {
        for keyword in ["any ", "some "] {
            let end = index + keyword.count
            guard end <= characters.count, String(characters[index..<end]) == keyword else { continue }
            return end
        }
        return nil
    }

    /// One past the last character of the existential that starts at `start`:
    /// the first delimiter at nesting depth zero, or the end of the string.
    /// `&` is not a delimiter — a composition is part of the existential.
    private static func existentialEnd(_ characters: [Character], from start: Int) -> Int {
        var depth = 0
        var index = start
        while index < characters.count {
            switch characters[index] {
            case "(", "[", "<":
                depth += 1
            case ")", "]", ">":
                if depth == 0 { return index }
                depth -= 1
            case ",":
                if depth == 0 { return index }
            case "-":
                if depth == 0, index + 1 < characters.count, characters[index + 1] == ">" { return index }
            default:
                break
            }
            index += 1
        }
        return characters.count
    }

    var needsSubjectMapToReturnType: Bool {
        if isTuple, let tuple {
            for element in tuple.elements {
                if element.typeName.isGeneric {
                    return false
                }
            }
            return false
        }

        if isArray, let array {
            return array.elementTypeName.needsSubjectMapToReturnType
        }

        if isDictionary, let dictionary {
            return dictionary.valueTypeName.needsSubjectMapToReturnType
        }

        return false
    }

    func hasComplexTypeWithSmartDefaultValue(isProperty: Bool) -> Bool {
        return (try? smartDefaultValueImplementation(isProperty: isProperty, mockVariablePrefix: "")) != nil
    }

    func smartDefaultValueImplementation(isProperty: Bool, mockVariablePrefix: String, forceCastingToReturnTypeName: Bool = false, requestedSubjectKind: SubjectKind = .automatic) throws -> (getterImplementation: SourceCode, mockedVariableHandlers: [SourceCode]) {
        if isGeneric,
            let generic = generic,
            generic.name == "Single" || generic.name == "Observable" || generic.name == "AnyObserver",
            generic.typeParameters.count == 1 {

            let returnTypeName = generic.typeParameters[0].typeName.mockTypeName
            let forceCasting = forceCastingToReturnTypeName && !isVoid ? " as! \(name.trimmingWhereClause())" : ""
            switch generic.name {
            case "Single":
                let getterImplementation = SourceCode("return Single.create { (observer: @escaping (SingleEvent<\(returnTypeName)>) -> ()) -> Disposable in") { [
                    SourceCode("""
                        return self.\(MockNaming.subject(mockVariablePrefix)).subscribe { (event: Event<\(returnTypeName)>) in
                                        switch event {
                                        case .next(let element):
                                            observer(.success(element))
                                        case .error(let error):
                                            observer(.failure(error))
                                        default:
                                            break
                                        }
                                    }
                        """)
                ]}
                let mockedVariableHandlers = [SourceCode("lazy var \(MockNaming.subject(mockVariablePrefix)) = PublishSubject<\(returnTypeName)>()")]
                return (getterImplementation, mockedVariableHandlers)
            case "Observable":
                let optionalMappingClauseForTupleTypes = generic.typeParameters[0].typeName.needsSubjectMapToReturnType ? ".map { $0 }" : ""
                let getterImplementation = SourceCode("return \(MockNaming.subject(mockVariablePrefix))\(optionalMappingClauseForTupleTypes).as\(generic.name)()\(forceCasting)")
                let mockedVariableHandlers = [SourceCode("lazy var \(MockNaming.subject(mockVariablePrefix)) = PublishSubject<\(returnTypeName)>()")]
                return (getterImplementation, mockedVariableHandlers)
            case "AnyObserver":
                let getterImplementation = SourceCode("return AnyObserver { [weak self] event in") { [
                    SourceCode("self?.\(MockNaming.eventCallCount(mockVariablePrefix)) += 1"),
                    SourceCode("self?.\(MockNaming.eventHandler(mockVariablePrefix))?(event)"),
                ]}
                let mockedVariableHandlers: [SourceCode] = [
                    SourceCode("var \(MockNaming.eventCallCount(mockVariablePrefix)): Int = 0"),
                    SourceCode("var \(MockNaming.eventHandler(mockVariablePrefix)): ((Event<\(returnTypeName)>) -> ())? = nil"),
                ]
                return (getterImplementation, mockedVariableHandlers)
            default:
                fatalError("Should not happen")
            }
        }

        if isGeneric,
            let generic = generic,
            generic.name == "AnyPublisher",
            generic.typeParameters.count == 2 {

            // Combine's `AnyPublisher<Output, Failure>` is backed by a subject the
            // test drives: `mock.<name>Subject.send(value)`. It is a
            // `PassthroughSubject`, for a variable and for a method alike — the
            // same rule the RxSwift branch above applies with `PublishSubject`.
            //
            // A subject that replays is the test's to supply, through the closure
            // every publisher member already has: `<name>GetHandler` on a
            // variable, `<name>Handler` on a method, each returning whatever
            // stream that test needs. Seeding by default instead would make the
            // double emit a value nobody wrote — an empty string, an empty
            // dictionary — the moment the code under test subscribes, and turn
            // the test's own `send` into a SECOND element (a bridge awaiting the
            // first value then resumes its continuation twice and traps). It is
            // also unopt-out-able by construction: assigning a
            // `PassthroughSubject` to a `CurrentValueSubject`-typed property does
            // not compile.
            //
            // `/// sourcery: subject = "CurrentValue"` states the seeded form at
            // the declaration, for the member where every test wants it;
            // requesting it for an `Output` with no default value is an error
            // rather than a silent downgrade.
            let outputTypeName = generic.typeParameters[0].typeName
            let outputType = outputTypeName.mockTypeName
            let failureType = generic.typeParameters[1].typeName.mockTypeName
            let forceCasting = forceCastingToReturnTypeName && !isVoid ? " as! \(name.trimmingWhereClause())" : ""
            let seedValue = outputTypeName.isVoid ? nil : try? outputTypeName.defaultValue()

            let subjectDecl: String
            switch requestedSubjectKind {
            case .currentValue:
                guard let seedValue = seedValue else {
                    throw MockError.unseedableSubject(typeName: outputTypeName, member: mockVariablePrefix)
                }
                subjectDecl = "CurrentValueSubject<\(outputType), \(failureType)>(\(seedValue))"
            case .passthrough:
                subjectDecl = "PassthroughSubject<\(outputType), \(failureType)>()"
            case .automatic:
                subjectDecl = "PassthroughSubject<\(outputType), \(failureType)>()"
            }

            let getterImplementation = SourceCode("return \(MockNaming.subject(mockVariablePrefix)).eraseToAnyPublisher()\(forceCasting)")
            let mockedVariableHandlers = [SourceCode("lazy var \(MockNaming.subject(mockVariablePrefix)) = \(subjectDecl)")]
            return (getterImplementation, mockedVariableHandlers)
        }

        if unwrappedTypeName == "AnyCancellable" {
            // The Combine twin of the `Disposable` case below. A registration
            // API hands back a token whose `cancel()` is the deregistration,
            // and that is what a spec needs to observe — so the default token
            // counts its own cancellation instead of trapping for want of a
            // handler.
            guard !isProperty else { throw MockError.noDefaultValue(typeName: self) } // Only functions with `AnyCancellable` return type are supported.
            let getterImplementation = SourceCode("return AnyCancellable { [weak self] in") { [
                SourceCode("self?.\(MockNaming.cancelCallCount(mockVariablePrefix)) += 1"),
                SourceCode("self?.\(MockNaming.cancelHandler(mockVariablePrefix))?()"),
            ]}
            let mockedVariableHandlers: [SourceCode] = [
                SourceCode("var \(MockNaming.cancelCallCount(mockVariablePrefix)): Int = 0"),
                SourceCode("var \(MockNaming.cancelHandler(mockVariablePrefix)): (() -> ())? = nil"),
            ]
            return (getterImplementation, mockedVariableHandlers)
        }

        if unwrappedTypeName == "Disposable" {
            guard !isProperty else { throw MockError.noDefaultValue(typeName: self) } // Only functions with `Disposable` return type are supported.
            let getterImplementation = SourceCode("return Disposables.create { [weak self] in") { [
                SourceCode("self?.\(MockNaming.disposeCallCount(mockVariablePrefix)) += 1"),
                SourceCode("self?.\(MockNaming.disposeHandler(mockVariablePrefix))?()"),
            ]}
            let mockedVariableHandlers: [SourceCode] = [
                SourceCode("var \(MockNaming.disposeCallCount(mockVariablePrefix)): Int = 0"),
                SourceCode("var \(MockNaming.disposeHandler(mockVariablePrefix)): (() -> ())? = nil"),
            ]
            return (getterImplementation, mockedVariableHandlers)
        }

        throw MockError.noDefaultValue(typeName: self)
    }
}
