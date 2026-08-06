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
        if let annotated = annotations(for: ["globalActor"]).first, !annotated.isEmpty {
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
        if annotations[caseInsensitiveKey: "uncheckedSendable"] != nil { return true }
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

extension SourceryRuntime.Annotated {
    /// `/// sourcery: subject = "CurrentValue"` / `"Passthrough"` on the member.
    /// Also accepts the full type names.
    var requestedSubjectKind: SubjectKind {
        switch annotations(for: ["subject"]).first?.lowercased() {
        case "currentvalue", "currentvaluesubject": return .currentValue
        case "passthrough", "passthroughsubject": return .passthrough
        default: return .automatic
        }
    }
}

private extension Dictionary where Key == String {
    subscript(caseInsensitiveKey key: Key) -> Value? {
        return first { $0.0.lowercased() == key.lowercased() }?.value
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

    var mockTypeName: String {
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

        if isOptional, unwrappedTypeName.hasPrefix("any ") {
            // Fix `any ProtocolName?` --> `(any ProtocolName)?`
            return "(\(unwrappedTypeName))?"
        }

        return actualTypeName?.mockTypeName ?? name
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
                        return self.\(mockVariablePrefix)Subject.subscribe { (event: Event<\(returnTypeName)>) in
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
                let mockedVariableHandlers = [SourceCode("lazy var \(mockVariablePrefix)Subject = PublishSubject<\(returnTypeName)>()")]
                return (getterImplementation, mockedVariableHandlers)
            case "Observable":
                let optionalMappingClauseForTupleTypes = generic.typeParameters[0].typeName.needsSubjectMapToReturnType ? ".map { $0 }" : ""
                let getterImplementation = SourceCode("return \(mockVariablePrefix)Subject\(optionalMappingClauseForTupleTypes).as\(generic.name)()\(forceCasting)")
                let mockedVariableHandlers = [SourceCode("lazy var \(mockVariablePrefix)Subject = PublishSubject<\(returnTypeName)>()")]
                return (getterImplementation, mockedVariableHandlers)
            case "AnyObserver":
                let getterImplementation = SourceCode("return AnyObserver { [weak self] event in") { [
                    SourceCode("self?.\(mockVariablePrefix)EventCallCount += 1"),
                    SourceCode("self?.\(mockVariablePrefix)EventHandler?(event)"),
                ]}
                let mockedVariableHandlers: [SourceCode] = [
                    SourceCode("var \(mockVariablePrefix)EventCallCount: Int = 0"),
                    SourceCode("var \(mockVariablePrefix)EventHandler: ((Event<\(returnTypeName)>) -> ())? = nil"),
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
            // test drives: `mock.<name>Subject.send(value)`. The subject kind is
            // chosen by whether a late subscriber needs the current value:
            //
            //   CurrentValueSubject — when `Output` has a default value, so the
            //     subject can be seeded and a subscriber attaching after the fact
            //     still receives one element. This is what a state stream needs.
            //   PassthroughSubject  — otherwise, because CurrentValueSubject has
            //     no initial value to construct; and for `Output == Void`, where
            //     a seeded subject would report a mutation as already completed
            //     to every subscriber. A Void publisher carries an event, not a
            //     state.
            //
            // Override per member with `/// sourcery: subject = "Passthrough"` or
            // `"CurrentValue"`; requesting `CurrentValue` for an `Output` with no
            // default value is an error rather than a silent downgrade.
            let outputTypeName = generic.typeParameters[0].typeName
            let outputType = outputTypeName.mockTypeName
            let failureType = generic.typeParameters[1].typeName.mockTypeName
            let forceCasting = forceCastingToReturnTypeName && !isVoid ? " as! \(name.trimmingWhereClause())" : ""
            let seedValue = outputTypeName.isVoid ? nil : try? outputTypeName.defaultValue()

            let subjectDecl: String
            switch requestedSubjectKind {
            case .currentValue:
                guard let seedValue = seedValue else {
                    throw MockError.noDefaultValue(typeName: outputTypeName)
                }
                subjectDecl = "CurrentValueSubject<\(outputType), \(failureType)>(\(seedValue))"
            case .passthrough:
                subjectDecl = "PassthroughSubject<\(outputType), \(failureType)>()"
            case .automatic:
                subjectDecl = seedValue.map { "CurrentValueSubject<\(outputType), \(failureType)>(\($0))" }
                    ?? "PassthroughSubject<\(outputType), \(failureType)>()"
            }

            let getterImplementation = SourceCode("return \(mockVariablePrefix)Subject.eraseToAnyPublisher()\(forceCasting)")
            let mockedVariableHandlers = [SourceCode("lazy var \(mockVariablePrefix)Subject = \(subjectDecl)")]
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
                SourceCode("self?.\(mockVariablePrefix)CancelCallCount += 1"),
                SourceCode("self?.\(mockVariablePrefix)CancelHandler?()"),
            ]}
            let mockedVariableHandlers: [SourceCode] = [
                SourceCode("var \(mockVariablePrefix)CancelCallCount: Int = 0"),
                SourceCode("var \(mockVariablePrefix)CancelHandler: (() -> ())? = nil"),
            ]
            return (getterImplementation, mockedVariableHandlers)
        }

        if unwrappedTypeName == "Disposable" {
            guard !isProperty else { throw MockError.noDefaultValue(typeName: self) } // Only functions with `Disposable` return type are supported.
            let getterImplementation = SourceCode("return Disposables.create { [weak self] in") { [
                SourceCode("self?.\(mockVariablePrefix)DisposeCallCount += 1"),
                SourceCode("self?.\(mockVariablePrefix)DisposeHandler?()"),
            ]}
            let mockedVariableHandlers: [SourceCode] = [
                SourceCode("var \(mockVariablePrefix)DisposeCallCount: Int = 0"),
                SourceCode("var \(mockVariablePrefix)DisposeHandler: (() -> ())? = nil"),
            ]
            return (getterImplementation, mockedVariableHandlers)
        }

        throw MockError.noDefaultValue(typeName: self)
    }
}
