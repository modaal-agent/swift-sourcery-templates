import Foundation
import SourceryRuntime

enum MockError: Error {
case noDefaultValue(typeName: TypeName)
case duplicateGenericTypeName(context: String)
case internalError(message: String)
}

private struct Constants {
    static let NEWL = ""
    static let genericTypePrefix = "_"
}

class MockGenerator {
    static func generate(for types: [Type]) throws -> String {
        var topScope = TopScope()

        for type in types {
            let mockVars = MockVar.from(type)
            let variablesToInit = mockVars.filter { $0.provideValueInInitializer }.map { (mockedVariableName: $0.mockedVariableName, variable: $0.variable, defaultValue: try? $0.variable.typeName.defaultValue()) }
            let mockMethods = try MockMethod.from(type, genericTypePrefix: Constants.genericTypePrefix)

            topScope += Constants.NEWL
            topScope += "// MARK: - \(type.name)"

            let genericTypes: [GenericTypeInfo] = (type.genericTypes + mockMethods.flatMap { $0.genericTypes }).merged()

            // Global actor isolation (e.g. `@MainActor`) is declared on the mock
            // class explicitly. Without it the conformance is inferred, which the
            // compiler rejects as soon as one requirement is `nonisolated`.
            if let globalActor = type.globalActorAttributeName {
                topScope += "@\(globalActor)"
            }

            // `@unchecked Sendable` is required — not merely nice — when the
            // protocol refines `Sendable`: a mock's call counters are mutable
            // stored properties, which a checked conformance rejects.
            let sendableConformance = type.requiresUncheckedSendable ? ", @unchecked Sendable" : ""

            var mock = SourceCode("final class \(type.name)Mock\(genericTypes.genericTypesModifier): \(type.isObjcProtocol ? "NSObject, " : "")\(type.name)\(sendableConformance)\(genericTypes.genericTypesConstraints)")
            mock.isBlockMandatory = true

            // generic typealiases
            mock += genericTypes.typealiasesDeclarations

            // variables
            let mockVarsFlattened = try mockVars.flatMap { try $0.mockImpl() }
            if !mockVarsFlattened.isEmpty {
                mock += Constants.NEWL
                mock += "// MARK: - Variables"
                mock += mockVarsFlattened
            }

            // initializer
            if !variablesToInit.isEmpty {
                let argumentList = variablesToInit.map {
                    let defaultValue = $0.defaultValue != nil ? " = \($0.defaultValue!)" : ""
                    return "\($0.mockedVariableName): \($0.variable.typeName.declaredName)\(defaultValue)"
                }.joined(separator: ", ")
                let initImpl = SourceCode("init(\(argumentList))")
                initImpl += variablesToInit.map { "self.\($0.mockedVariableName) = \($0.mockedVariableName)" }
                mock += Constants.NEWL
                mock += "// MARK: - Initializer"
                mock += initImpl
            }

            // methods
            let mockMethodsFlattened = try mockMethods.flatMap { try $0.mockImpl() }
            if !mockMethodsFlattened.isEmpty {
                mock += Constants.NEWL
                mock += "// MARK: - Methods"
                mock += mockMethodsFlattened
            }

            topScope += mock
        }

        return topScope.indentedSourcecode()
    }
}

private extension SourceryRuntime.`Type` {
    var isObjcProtocol: Bool {
        return annotations["ObjcProtocol"] != nil
            || inheritedTypes.contains("NSObjectProtocol")
    }
}

private extension SourceryRuntime.`Type` {
    var genericTypes: [GenericTypeInfo] {
        let associatedTypes = annotatedAssociatedTypes()
        return associatedTypes
    }
}

private extension Collection where Element == GenericTypeInfo {

    /// For a given list of generic types, creates a corresponding type declaration modifier string.
    /// E.g., for a list ["T1", "T2"] this will create "<_T1, _T2>" modifier string (where "_" is the value of genericTypePrefix).
    var genericTypesModifier: String {
        let types = sorted { $0.genericType < $1.genericType }.map { "\(Constants.genericTypePrefix)\($0.genericType)" }
        return !types.isEmpty ? "<\(types.joined(separator: ", "))>" : ""
    }

    /// For a given list of generic types, some of which have type constraints, creates a "where" clause for the type declaration.
    /// E.g., for a list ["T1: RawRepresentable", "T1: Hashable", "T2"] this will create "where _T1: RawRepresentable, _T1: Hashable" modifier string (where "_" is the value of genericTypePrefix).
    var genericTypesConstraints: String {
        let constraints = sorted { $0.genericType < $1.genericType }.flatMap { genericType in return genericType.constraints.map { "\(Constants.genericTypePrefix)\($0)" }.sorted() }
        return !constraints.isEmpty ? " where \(constraints.joined(separator: ", "))" : ""
    }

    var typealiasesDeclarations: [String] {
        guard !isEmpty else { return [] }
        var result: [String] = []
        result.append(Constants.NEWL)
        result.append("// MARK: - Generic typealiases")
        result.append(contentsOf: sorted { $0.genericType < $1.genericType }.map { "typealias \($0.genericType) = \(Constants.genericTypePrefix)\($0.genericType)" })
        return result
    }
}

extension MockError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noDefaultValue(let typeName): return "Unable to generate default value for \(typeName)"
        case .duplicateGenericTypeName(let context): return "Duplicate generic type name found while generating mock implementation: \(context)"
        case .internalError(let message): return "Internal error: \(message)"
        }
    }
}

extension MockError: CustomStringConvertible {
    var description: String {
        return errorDescription ?? String(describing: self)
    }
}

extension MockError: CustomDebugStringConvertible {
    var debugDescription: String {
        return errorDescription ?? String(describing: self)
    }
}
