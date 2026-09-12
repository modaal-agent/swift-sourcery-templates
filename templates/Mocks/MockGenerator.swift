import Foundation
import SourceryRuntime

enum MockError: Error {
case noDefaultValue(typeName: TypeName)
/// `subject = "CurrentValue"` on a member whose `Output` cannot be constructed.
/// Distinct from `noDefaultValue`, which a caller may legitimately catch to fall
/// through to a shape it does handle: this one is the author asking for
/// something impossible and must reach them.
case unseedableSubject(typeName: TypeName, member: String)
case duplicateGenericTypeName(context: String)
/// Two members of one mock would carry the same name. The generated file
/// would not compile, and before this case it did not — with nothing from
/// the template saying which two members collided (`spec.md` D9).
case collidingMemberNames(typeName: String, memberName: String)
/// A requirement declaring `throws(E)`. The templates write bare `throws`,
/// and a witness throwing `any Error` does not satisfy it — so the
/// requirement is refused in generation rather than at the consumer's
/// conformance (`spec.md` §2.6, §8 question 1).
case typedThrowsUnsupported(typeName: String, member: String, errorTypeName: String)
/// An `AnyPublisher` requirement declared `{ get async }` or `{ get throws }`.
/// The construct it returns reads its handler from inside a synchronous
/// closure, which cannot await or rethrow (`spec.md` §2.7).
case effectfulStreamRequirement(typeName: String, member: String)
case internalError(message: String)
}

private struct Constants {
    static let NEWL = ""
    static let genericTypePrefix = "_"
}

class MockGenerator {
    static func generate(for types: [Type]) throws -> String {
        // A scan that matches nothing still renders content. The engine skips
        // writing a whitespace-only file, and a pipeline that fingerprints the
        // committed output needs the file to exist from its first generation —
        // so the empty case emits one marker comment where the first type
        // block would sit, and the first annotation replaces it with a mock.
        guard !types.isEmpty else {
            return "\n// No protocols annotated `CreateMock` under the scanned sources."
        }
        var topScope = TopScope()

        // The naming rule, stated once at the top of the file (D14(a)).
        topScope += Constants.NEWL
        topScope += MockNaming.fileNamingHeaderLines

        for type in types {
            let mockVars = MockVar.from(type)
            let variablesToInit = mockVars.filter { $0.provideValueInInitializer }.map { (mockedVariableName: $0.mockedVariableName, variable: $0.variable, defaultValue: try? $0.variable.typeName.defaultValue()) }
            let mockMethods = try MockMethod.from(type, genericTypePrefix: Constants.genericTypePrefix)

            topScope += Constants.NEWL
            topScope += "// MARK: - \(type.name)"

            // The rule again, in the slice an agent lands in (D14(b)), and then
            // this class's index of the members that do not follow it (D15(b)).
            // Both lines of the index and the line above the witness come from
            // one call per method, so they cannot disagree.
            topScope += MockNaming.classNamingHeaderLines
            let namingComments = mockMethods.compactMap { $0.namingComment }
            if !namingComments.isEmpty {
                topScope += MockNaming.namingIndexHeaderLine
                topScope += namingComments.map { MockNaming.namingIndexLine($0) }
            }

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
                // The parameter keeps the requirement's own name and the
                // assignment targets the store, so a consumer's `Mock(analytics:)`
                // is unchanged and construction moves no counter (§2.5).
                initImpl += variablesToInit.map { "self.\(MockNaming.store($0.mockedVariableName)) = \($0.mockedVariableName)" }
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

            // Every name the class declares, checked once, after the members
            // that produce them have all been emitted. It covers a requirement
            // colliding with another requirement's bookkeeping, two
            // requirements producing one prefix, and the stream members' own
            // names — whichever branch emitted them.
            try MockNaming.checkForCollisions(
                amongMemberDeclarations: mock.nested.map { $0.line },
                typeName: type.name)

            topScope += mock
        }

        return topScope.indentedSourcecode()
    }
}

private extension SourceryRuntime.`Type` {
    var isObjcProtocol: Bool {
        return isAnnotated(AnnotationRegistry.objcProtocolMock)
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
        case .unseedableSubject(let typeName, let member):
            return """
                `sourcery: subject = "CurrentValue"` on `\(member)`: a CurrentValueSubject has to be \
                seeded and there is no default value for \(typeName). Drop the annotation and set \
                `\(member)GetHandler` in the test to a stream that replays, or give the type a default value.
                """
        case .duplicateGenericTypeName(let context): return "Duplicate generic type name found while generating mock implementation: \(context)"
        case .typedThrowsUnsupported(let typeName, let member, let errorTypeName):
            return """
                `\(typeName).\(member)` is declared `throws(\(errorTypeName))`. The generated mock writes \
                bare `throws`, and a witness that throws `any Error` does not satisfy a requirement \
                that throws `\(errorTypeName)`. Declare the requirement `throws` on the protocol, or \
                write this double by hand.
                """
        case .effectfulStreamRequirement(let typeName, let member):
            return """
                `\(typeName).\(member)` returns a publisher and is declared `async` or `throws`. \
                The generated member hands back a `Deferred` whose closure reads \
                `\(member)GetHandler` when the code under test subscribes, and that closure is \
                synchronous. Drop the effects from the requirement, or return the stream from a \
                method instead, where the handler is called with the method's own effects.
                """
        case .collidingMemberNames(let typeName, let memberName):
            return """
                `\(typeName)Mock` would declare `\(memberName)` twice. A requirement of \
                `\(typeName)` collides with a bookkeeping member generated for another \
                requirement, or two requirements produce the same name. Rename the requirement, \
                or — for a method — name its members outright with \
                `/// sourcery: methodName = "customName"` on the declaration.
                """
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
