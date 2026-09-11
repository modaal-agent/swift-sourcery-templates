import Foundation
import SourceryRuntime

class MockVar {
    let variable: SourceryRuntime.Variable
    fileprivate let type: SourceryRuntime.`Type`

    var mockedVariableName: String {
        return MockNaming.variablePrefix(name: variable.name)
    }

    init(variable: SourceryRuntime.Variable, type: SourceryRuntime.`Type`) {
        self.variable = variable
        self.type = type
    }

    static func from(_ type: Type) -> [MockVar] {
        let allVariables = type.allVariables.filter { !$0.isStatic && $0.definedInType != nil && $0.definedInType?.isExtension == false }.uniqueVariables
        return allVariables.map { MockVar(variable: $0, type: type) }.sorted { $0.mockedVariableName < $1.mockedVariableName }
    }
}

extension MockVar {

    // Does this variable require init()?
    var provideValueInInitializer: Bool {
        return !variable.typeName.hasComplexTypeWithSmartDefaultValue(isProperty: true)
            && (variable.isAnnotatedInit || !variable.typeName.hasDefaultValue)
            && !variable.isAnnotatedHandler
    }

    /// See `MockMethod.isNonisolated` — the modifier is emitted only on an
    /// isolated mock, where it changes the member's meaning.
    fileprivate var isNonisolated: Bool {
        return type.emitsNonisolatedMembers && variable.isDeclaredNonisolated
    }

    fileprivate var isolationDecl: String {
        return isNonisolated ? "nonisolated " : ""
    }

    fileprivate var storageIsolationDecl: String {
        return isNonisolated ? "nonisolated(unsafe) " : ""
    }

    /// `nil` when this variable's type has no smart default *of a shape this
    /// branch handles* — an `AnyCancellable` or `Disposable` property, say, which
    /// falls through to plain storage below. An impossible `subject` annotation
    /// is not that case and is rethrown: swallowing it emitted a stored property
    /// with no initializer, and the generated file did not compile.
    private func smartDefaultValueImplementation() throws -> (getterImplementation: SourceCode, mockedVariableHandlers: [SourceCode])? {
        do {
            return try variable.typeName.smartDefaultValueImplementation(
                isProperty: true,
                mockVariablePrefix: mockedVariableName,
                requestedSubjectKind: variable.requestedSubjectKind)
        } catch MockError.unseedableSubject(let typeName, let member) {
            throw MockError.unseedableSubject(typeName: typeName, member: member)
        } catch {
            return nil
        }
    }

    func mockImpl() throws -> [SourceCode] {
        let mockedVariableImplementation: SourceCode
        let mockedVariableHandlers = TopScope()

        if !variable.isMutable,
            variable.typeName.hasComplexTypeWithSmartDefaultValue(isProperty: true),
            let smartDefaultValueImplementation = try smartDefaultValueImplementation() {

            mockedVariableImplementation = SourceCode("\(isolationDecl)var \(variable.name): \(variable.typeName.declaredName)") {[
                SourceCode("\(MockNaming.getCount(mockedVariableName)) += 1"),
                SourceCode("if let handler = \(MockNaming.getHandler(mockedVariableName))") {[
                    SourceCode("return handler()")
                ]},
                smartDefaultValueImplementation.getterImplementation
            ]}
            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getCount(mockedVariableName)): Int = 0"
            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getHandler(mockedVariableName)): (() -> \(variable.typeName.declaredName))? = nil"
            mockedVariableHandlers += smartDefaultValueImplementation.mockedVariableHandlers.isolated(storageIsolationDecl)
        } else {
            // Every property requirement is a computed accessor that counts the
            // read (§2.5). What differs between the two branches below is where
            // the value comes from: `/// sourcery: handler` has no storage and
            // traps when the test has set no handler, everything else falls back
            // to the store the accessors sit over.
            let getterImplementation: [SourceCode] = [
                SourceCode("\(MockNaming.getCount(mockedVariableName)) += 1"),
                SourceCode("if let handler = \(MockNaming.getHandler(mockedVariableName))") {[
                    SourceCode("return handler()")
                ]},
                variable.isAnnotatedHandler
                    ? SourceCode("fatalError(\"\(MockNaming.getHandlerExpectedMessage(prefix: mockedVariableName))\")")
                    : SourceCode("return \(MockNaming.store(mockedVariableName))")
            ]

            // The witness stays settable wherever it is settable today: a
            // read-only requirement backed by a `var` store was emitted as a
            // settable stored property, and a test re-seeds it by assignment.
            // `const` and `handler` are the two that were not — the first has a
            // `let`, the second has no storage at all.
            //
            // `<var>SetCount` counts a write to a `{ get set }` requirement, and
            // only that (§2.3): a re-seed of a read-only requirement was
            // uncounted before this change and stays uncounted.
            let hasSetter = variable.isMutable || !(variable.isAnnotatedConst || variable.isAnnotatedHandler)
            var setterImplementation: [SourceCode] = []
            if variable.isMutable {
                // `didSet` on a stored property was the old shape, and a stored
                // property cannot count a read.
                setterImplementation += [SourceCode("\(MockNaming.setCount(mockedVariableName)) += 1")]
            }
            if !variable.isAnnotatedHandler {
                setterImplementation += [SourceCode("\(MockNaming.store(mockedVariableName)) = newValue")]
            }

            if hasSetter {
                mockedVariableImplementation = SourceCode("\(isolationDecl)var \(variable.name): \(variable.typeName.declaredName)") {[
                    SourceCode("get", nested: getterImplementation),
                    SourceCode("set", nested: setterImplementation)
                ]}
            } else {
                mockedVariableImplementation = SourceCode("\(isolationDecl)var \(variable.name): \(variable.typeName.declaredName)", nested: getterImplementation)
            }

            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getCount(mockedVariableName)): Int = 0"
            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getHandler(mockedVariableName)): (() -> \(variable.typeName.declaredName))? = nil"
            if variable.isMutable {
                mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.setCount(mockedVariableName)): Int = 0"
            }
            if !variable.isAnnotatedHandler {
                // `/// sourcery: const` makes the store a `let`, so the value is
                // fixed at construction and the accessor is get-only.
                let storeDecl = !variable.isMutable && variable.isAnnotatedConst ? "let" : "var"
                let storeName = MockNaming.store(mockedVariableName)
                if !variable.isAnnotatedInit, variable.typeName.hasDefaultValue, let defaultValue = try? variable.typeName.defaultValue() {
                    mockedVariableHandlers += "\(storageIsolationDecl)\(storeDecl) \(storeName): \(variable.typeName.declaredName) = \(defaultValue)"
                } else {
                    // No default value: the mock class's initializer seeds it.
                    mockedVariableHandlers += "\(storageIsolationDecl)\(storeDecl) \(storeName): \(variable.typeName.declaredName)"
                }
            }
        }
        var topScope = TopScope()
        topScope += mockedVariableImplementation
        topScope += mockedVariableHandlers.nested
        return topScope.nested
    }
}

private extension Collection where Element: SourceryRuntime.Variable {
    var uniqueVariables: [SourceryRuntime.Variable] {
        return reduce(into: [], { (result, element) in
            guard !result.contains(where: { $0.name == element.name }) else { return }
            result.append(element)
        })
    }
}
