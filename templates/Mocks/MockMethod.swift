import Foundation
import SourceryRuntime

class MockMethod {
    fileprivate let type: SourceryRuntime.`Type`
    let method: SourceryRuntime.Method
    fileprivate let genericTypePrefix: String
    fileprivate let useShortName: Bool
    fileprivate let useReturnTypeInName: Bool

    init(type: SourceryRuntime.`Type`, method: SourceryRuntime.Method, genericTypePrefix: String, useShortName: Bool, useReturnTypeInName: Bool = false) {
        self.type = type
        self.method = method
        self.genericTypePrefix = genericTypePrefix
        self.useShortName = useShortName
        self.useReturnTypeInName = useReturnTypeInName
    }

    static func from(_ type: Type, genericTypePrefix: String) throws -> [MockMethod] {
        let allMethods = type.allMethods.filter { !$0.isStatic && $0.definedInType != nil && $0.definedInType?.isExtension == false }.uniquesWithoutGenericConstraints()
        let mockedMethods = allMethods
            .map { MockMethod(type: type, method: $0, genericTypePrefix: genericTypePrefix, useShortName: true) }
            .minimumNonConflictingPermutation
        guard !mockedMethods.hasDuplicateMockedMethodNames else {
            throw MockError.internalError(message: "Mock generator: not all duplicates resolved: \(mockedMethods.map { $0.mockedMethodName })!")
        }
        return mockedMethods.sorted { $0.mockedMethodName < $1.mockedMethodName }
    }
}

extension MockMethod {
    var isVoid: Bool {
        return method.returnTypeName.isVoid
    }

    var isGeneric: Bool {
        return method.isGeneric
    }

    var genericTypes: [GenericTypeInfo] {
        return method.annotatedGenericTypes()
    }
}

extension MockMethod {
    fileprivate var annotatedMethodName: String? {
        return method.annotations(for: ["methodName"]).first
    }

    fileprivate var mockedMethodName: String {
        if let annotatedMethodName = annotatedMethodName {
            return annotatedMethodName
        }
        var result: [String] = [method.callName]
        if !useShortName {
            result += method.parameters.map {
                let argumentLabel = $0.argumentLabel == nil ? "" : $0.argumentLabel != $0.name ? $0.argumentLabel!.uppercasedFirstLetter() : ""
                return "\(argumentLabel)\($0.name.uppercasedFirstLetter())"
            }
        }
        if useReturnTypeInName {
            result += [returnTypeDiscriminator]
        }
        return result.joined().swiftifiedMethodName
    }

    /// Suffix derived from the method's return type, used to disambiguate
    /// overloads that share the same name *and* the same parameter list but
    /// differ only by return type (e.g., a refining protocol overriding
    /// `func data() -> [String: Any]?` with `func data() -> [String: Any]`).
    /// Such overloads cannot be distinguished by parameter labels alone.
    fileprivate var returnTypeDiscriminator: String {
        return method.returnTypeName.name.returnTypeDiscriminatorSuffix
    }

    /// `nonisolated` is restated on the mock only when the mock class carries a
    /// global actor — that is the case where the modifier changes the meaning of
    /// the member rather than repeating the default.
    fileprivate var isNonisolated: Bool {
        return type.emitsNonisolatedMembers && method.isDeclaredNonisolated
    }

    /// Modifier for the generated `func`.
    fileprivate var isolationDecl: String {
        return isNonisolated ? "nonisolated " : ""
    }

    /// Modifier for the generated bookkeeping storage. A `nonisolated` member
    /// mutates its own call counter, which the compiler rejects when that
    /// counter stays actor-isolated; `nonisolated(unsafe)` is what a mutable
    /// stored property outside the actor requires.
    fileprivate var storageIsolationDecl: String {
        return isNonisolated ? "nonisolated(unsafe) " : ""
    }

    func mockImpl() throws -> [SourceCode] {
        var mockMethodHandlers = TopScope()

        let mockCallCount = mockCallCountImpl
        mockMethodHandlers += mockCallCount.1

        var mockHandler = mockHandlerImpl
        mockMethodHandlers += mockHandler.1

        // func declaration
        var methodImpl = SourceCode("\(isolationDecl)func \(method.shortName)(\(method.methodParametersDecl))\(method.asyncDecl)\(method.throwingDecl)\(method.returnTypeDecl)")

        // Increment usage call count.
        methodImpl += "\(mockCallCount.0) += 1"

        // Call the handler.
        methodImpl += mockHandlerCallImpl

        // Fallback return value.
        if isVoid {
            // No return value
        } else if method.isOptionalReturnType {
            // Return nil
            methodImpl += "return nil"
        } else {
            // Do something smart
            if method.returnTypeName.hasComplexTypeWithSmartDefaultValue(isProperty: false) {
                let smartDefaultValueImplementation = try method.returnTypeName.smartDefaultValueImplementation(
                    isProperty: false,
                    mockVariablePrefix: mockedMethodName,
                    forceCastingToReturnTypeName: isGeneric,
                    requestedSubjectKind: method.requestedSubjectKind)

                methodImpl += smartDefaultValueImplementation.0
                mockMethodHandlers += smartDefaultValueImplementation.1.isolated(storageIsolationDecl)
            } else if method.returnTypeName.hasDefaultValue, let defaultValue = try? method.returnTypeName.defaultValue() {
                methodImpl += SourceCode("return \(defaultValue)")
            } else {
                // fatal
                methodImpl += "fatalError(\"\(mockHandler.0) expected to be set.\")"
            }
        }

        var result = TopScope()
        result += methodImpl
        result += mockMethodHandlers.nested
        return result.nested
    }

    private var mockedVarCallCountName: String {
        return "\(mockedMethodName)CallCount"
    }

    private var mockCallCountImpl: (String, SourceCode) {
        return (mockedVarCallCountName, SourceCode("\(storageIsolationDecl)var \(mockedVarCallCountName): Int = 0"))
    }

    private var mockMethodHandlerName: String {
        return "\(mockedMethodName)Handler"
    }

    private var mockMethodHandlerReturnType: String {
        return !isVoid ? method.returnTypeName.declaredName.trimmingWhereClause() : ""
    }

    private var mockHandlerImpl: (String, SourceCode) {
        let handlerParameters = method.parameters.map {
            return "_ \($0.name): \($0.closureAttributesDecl)\($0.typeName.declaredName)"
        }.joined(separator: ", ")
        return (mockMethodHandlerName, SourceCode("\(storageIsolationDecl)var \(mockMethodHandlerName): ((\(handlerParameters))\(method.asyncDecl)\(method.throwingHandlerDecl) -> (\(mockMethodHandlerReturnType)))? = nil"))
    }

    private var mockHandlerCallImpl: SourceCode {
        let returning = isVoid ? "" : "return "
        let parameters = method.parameters
            .map {
                let referenceTaking = $0.`inout` ? "&" : ""
                let parameterName = "\(referenceTaking)\($0.name)"
                if isGeneric, let extractedAnnotatedGenericTypesPlaceholder = $0.annotations(for: ["annotatedGenericType", "annotatedGenericTypes", "genericTypePlaceholder", "genericTypesPlaceholder"]).first {
                    let forceCastingToGenericParameterType = " as! \(extractedAnnotatedGenericTypesPlaceholder.resolvingGenericPlaceholders(prefix: genericTypePrefix))"
                    return "\(parameterName)\(forceCastingToGenericParameterType)"
                } else {
                    return parameterName
                }
            }
            .joined(separator: ", ")
        let forceCastingToGenericReturnValue = isGeneric && !isVoid ? " as! \(mockMethodHandlerReturnType)" : ""
        let invocationThrowing = method.`throws` ? "try " : method.`rethrows` ? "try! " : ""
        let invocationAwaiting = method.isAsync ? "await " : ""
        let handlerName = mockHandlerImpl.0
        return SourceCode("if let __\(handlerName) = self.\(handlerName)") {[
            SourceCode("\(returning)\(invocationThrowing)\(invocationAwaiting)__\(handlerName)(\(parameters))\(forceCastingToGenericReturnValue)")
        ]}
    }
}

private struct Regex {
    static let placeholderPattern = "\\{([^\\}]+)\\}"
}

private extension String {
    var swiftifiedMethodName: String {
        return self
            .replacingOccurrences(of: "(", with: "_")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "`", with: "")
            .camelCased()
            .lowercasedFirstWord()
    }

    func resolvingGenericPlaceholders(prefix genericTypePrefix: String) -> String {
        return replacingOccurrences(of: Regex.placeholderPattern, with: "\(genericTypePrefix)$1", options: .regularExpression)
    }

    /// Sanitizes a return-type string into a stable, readable suffix suitable
    /// for inclusion in a mock variable name. Used as the last-resort
    /// disambiguator for overloads that share name and parameter list.
    ///
    /// Examples:
    /// - `[String: Any]?` → `StringAnyOptional`
    /// - `[String: Any]`  → `StringAny`
    /// - `String?`        → `StringOptional`
    /// - `String`         → `String`
    var returnTypeDiscriminatorSuffix: String {
        var sanitized = self
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
}

private extension MockMethod {
    var shortNameKey: String {
        return method.shortName.swiftifiedMethodName
    }
}

private extension SourceryRuntime.Method {
    var methodParametersDecl: String {
        return parameters
            .map { $0.parametersDecl }
            .joined(separator: ", ")
    }

    var asyncDecl: String {
        return isAsync ? " async" : ""
    }

    var throwingDecl: String {
        return self.`throws` ? " throws" : self.`rethrows` ? " rethrows" : ""
    }

    var throwingHandlerDecl: String {
        return self.`throws` || self.`rethrows` ? " throws" : ""
    }

    var returnTypeDecl: String {
        return !returnTypeName.isVoid ? " -> \(returnTypeName.declaredName)" : ""
    }
}

extension SourceryRuntime.MethodParameter {
    /// Closure-type attributes that have to survive into the mock, in
    /// declaration order.
    ///
    /// `typeName.name` strips type attributes, and `typeName.asSource` carries
    /// all of them — including `@autoclosure`, which is legal on a function
    /// parameter but not on a closure type parameter, so neither is usable
    /// directly. Each attribute is checked and emitted explicitly.
    ///
    /// - `@escaping` — the handler must be able to store the closure and call
    ///   it later, which is the point of capturing it.
    /// - `@Sendable` — without it the captured closure's *type* is not
    ///   Sendable, so handing it to anything `@Sendable`-constrained fails with
    ///   "converting non-Sendable function value to '@Sendable …' may introduce
    ///   data races". Conformance holds either way (a witness taking a
    ///   non-Sendable closure is the more general one), so this is about what a
    ///   spec can do with what it captured, not about the mock compiling.
    var closureAttributesDecl: String {
        guard typeName.isClosure else { return "" }
        var attributesDecl = ""
        if typeName.attributes["escaping"] != nil { attributesDecl += "@escaping " }
        if typeName.attributes["Sendable"] != nil { attributesDecl += "@Sendable " }
        return attributesDecl
    }

    var parametersDecl: String {
        let argumentLabel = argumentLabel == nil ? "_ " : argumentLabel != name ? "\(argumentLabel!) " : ""
        return "\(argumentLabel)\(name): \(closureAttributesDecl)\(typeName.declaredName)"
    }
}

private extension Collection where Element == MockMethod {
    /// If all method mocks were created with `useShortName: true`, then the resulting mock might have duplicate backing variable names for methods, e.g.:
    /// ```
    /// func updateTips(_ tips: [Tip])
    /// func updateTips(with: AnySequence<Tip>) throws
    /// ```
    /// would both produce `var updateTipsCallCount: Int = 0`, which will break the build.
    /// This method finds such occurrences and tries to use fully-qualified names of the method to produce mock variables for groups of duplicate methods.
    /// While doing so, it will try to use `useShortName: true` for the shortest method name, to produce a little bit more readable/deterministic mock class,
    /// where the existing implementation would not change if new method overrides are added later with more parameters.
    var minimumNonConflictingPermutation: [MockMethod] {
        return reduce(into: [:]) { (partialResult: inout [String: [MockMethod]], nextItem: MockMethod) in
                let key = nextItem.shortNameKey
                var group = partialResult[key] ?? []
                group.append(nextItem)
                partialResult[key] = group
            }
            .map { $0.1.makeUniqueByUsingLongNamesExceptForFewestArgumentMethod() }
            .joined()
            .map { $0 }
    }

    private func makeUniqueByUsingLongNamesExceptForFewestArgumentMethod() -> [MockMethod] {
        guard count != 1 else { return Array(self) }
        func areInAscendingOrder(lhs: MockMethod, rhs: MockMethod) -> Bool {
            if lhs.method.parameters.count < rhs.method.parameters.count {
                // Use the method with the fewest number of parameters
                return true
            }
            if lhs.method.parameters.count == rhs.method.parameters.count,
                let firstParameterLhs = lhs.method.parameters.first,
                let firstParameterRhs = rhs.method.parameters.first {
                // If two methods have the same number of parameters, but one has shorter syntax by not requiring parameter label, use it instead.
                return firstParameterLhs.argumentLabel == nil && firstParameterRhs.argumentLabel != nil
            }
            // Otherwise, use the other one.
            return false
        }
        guard let fewestArgumentsMethod = min(by: areInAscendingOrder), let largestArgumentsMethod = max(by: areInAscendingOrder) else { fatalError("Should not happen.") }
        if fewestArgumentsMethod.method.parameters.parametersCountAppendingOneForArgumentLabel == largestArgumentsMethod.method.parameters.parametersCountAppendingOneForArgumentLabel {
            // min and max methods in the collection have exactly the same number of parameters, we can't choose one over another,
            // so use long form for all.
            return makeUniqueByUsingLongNames()
        }
        let copy = map { MockMethod(type: $0.type, method: $0.method, genericTypePrefix: $0.genericTypePrefix, useShortName: $0 === fewestArgumentsMethod) }
        guard !copy.hasDuplicateMockedMethodNames else {
            return makeUniqueByUsingLongNames()
        }
        return copy
    }

    private func makeUniqueByUsingLongNames() -> [MockMethod] {
        let longNames = map { MockMethod(type: $0.type, method: $0.method, genericTypePrefix: $0.genericTypePrefix, useShortName: false) }
        guard longNames.hasDuplicateMockedMethodNames else { return longNames }
        // Long names still collide — overloads share the same parameter list
        // but differ only by return type (e.g., a refining protocol overriding
        // `data() -> [String: Any]?` with `data() -> [String: Any]`). Append a
        // return-type-derived suffix to disambiguate.
        return makeUniqueByAppendingReturnTypeDiscriminator()
    }

    private func makeUniqueByAppendingReturnTypeDiscriminator() -> [MockMethod] {
        return map {
            MockMethod(
                type: $0.type,
                method: $0.method,
                genericTypePrefix: $0.genericTypePrefix,
                useShortName: false,
                useReturnTypeInName: true
            )
        }
    }

    var hasDuplicateMockedMethodNames: Bool {
        var mockedMethodNames = Set<String>()
        for nextItem in self {
            let key = nextItem.mockedMethodName
            if mockedMethodNames.contains(key) {
                return true
            }
            mockedMethodNames.insert(key)
        }
        return false
    }
}

private extension Collection where Element == SourceryRuntime.MethodParameter {
    var parametersCountAppendingOneForArgumentLabel: Int {
        return (first?.argumentLabel != nil ? 1 : 0) + count
    }
}

private extension Collection where Element == SourceryRuntime.Method {
    /// Courtesy of https://github.com/MakeAWishFoundation/SwiftyMocky/blob/develop/Sources/Templates/Mock.swifttemplate
    func uniques() -> [SourceryRuntime.Method] {
        func returnTypeStripped(_ method: SourceryRuntime.Method) -> String {
            let returnTypeRaw = "\(method.returnTypeName)"
            var stripped: String = {
                guard let range = returnTypeRaw.range(of: "where") else { return returnTypeRaw }
                var stripped = returnTypeRaw
                stripped.removeSubrange((range.lowerBound)...)
                return stripped
            }()
            stripped = stripped.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            return stripped
        }

        func areSameParams(_ p1: SourceryRuntime.MethodParameter, _ p2: SourceryRuntime.MethodParameter) -> Bool {
            guard p1.argumentLabel == p2.argumentLabel else { return false }
            guard p1.name == p2.name else { return false }
            guard p1.argumentLabel == p2.argumentLabel else { return false }
            guard p1.typeName.name == p2.typeName.name else { return false }
            guard p1.actualTypeName?.name == p2.actualTypeName?.name else { return false }
            return true
        }

        func areSameMethods(_ m1: SourceryRuntime.Method, _ m2: SourceryRuntime.Method) -> Bool {
            guard m1.name != m2.name else { return m1.returnTypeName == m2.returnTypeName }
            guard m1.selectorName == m2.selectorName else { return false }
            guard m1.parameters.count == m2.parameters.count else { return false }

            let p1 = m1.parameters
            let p2 = m2.parameters

            for i in 0..<p1.count {
                if !areSameParams(p1[i],p2[i]) { return false }
            }

            return m1.returnTypeName == m2.returnTypeName
        }

        return reduce([], { (result, element) -> [SourceryRuntime.Method] in
            guard !result.contains(where: { areSameMethods($0,element) }) else { return result }
            return result + [element]
        })
    }

    /// Courtesy of https://github.com/MakeAWishFoundation/SwiftyMocky/blob/develop/Sources/Templates/Mock.swifttemplate
    func uniquesWithoutGenericConstraints() -> [SourceryRuntime.Method] {
        func returnTypeStripped(_ method: SourceryRuntime.Method) -> String {
            let returnTypeRaw = "\(method.returnTypeName)"
            var stripped: String = {
                guard let range = returnTypeRaw.range(of: "where") else { return returnTypeRaw }
                var stripped = returnTypeRaw
                stripped.removeSubrange((range.lowerBound)...)
                return stripped
            }()
            stripped = stripped.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            return stripped
        }

        func areSameParams(_ p1: SourceryRuntime.MethodParameter, _ p2: SourceryRuntime.MethodParameter) -> Bool {
            guard p1.argumentLabel == p2.argumentLabel else { return false }
            guard p1.name == p2.name else { return false }
            guard p1.argumentLabel == p2.argumentLabel else { return false }
            guard p1.typeName.name == p2.typeName.name else { return false }
            guard p1.actualTypeName?.name == p2.actualTypeName?.name else { return false }
            return true
        }

        func areSameMethods(_ m1: SourceryRuntime.Method, _ m2: SourceryRuntime.Method) -> Bool {
            guard m1.name != m2.name else { return returnTypeStripped(m1) == returnTypeStripped(m2) }
            guard m1.selectorName == m2.selectorName else { return false }
            guard m1.parameters.count == m2.parameters.count else { return false }

            let p1 = m1.parameters
            let p2 = m2.parameters

            for i in 0..<p1.count {
                if !areSameParams(p1[i],p2[i]) { return false }
            }

            return returnTypeStripped(m1) == returnTypeStripped(m2)
        }

        return reduce([], { (result, element) -> [SourceryRuntime.Method] in
            guard !result.contains(where: { areSameMethods($0,element) }) else { return result }
            return result + [element]
        })
    }
}
