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

    /// The effects the requirement declares, in the order Swift writes them.
    /// `var x: T { get async throws }` is parsed — `Variable.isAsync` and
    /// `Variable.throws` — and was ignored until §2.6, which emits the accessor
    /// the requirement declares rather than a stored property that does not
    /// satisfy it.
    ///
    /// Swift has no effectful setter, so an effectful requirement is get-only
    /// and generates no `<var>SetCount`. `_<var>` stays assignable, which is how
    /// a test seeds it.
    fileprivate var effectsDecl: String {
        return "\(variable.isAsync ? " async" : "")\(variable.`throws` ? " throws" : "")"
    }

    /// `try `/`await ` for the call into `<var>GetHandler`.
    fileprivate var effectfulCallDecl: String {
        return "\(variable.`throws` ? "try " : "")\(variable.isAsync ? "await " : "")"
    }

    fileprivate var hasEffects: Bool {
        return variable.isAsync || variable.`throws`
    }

    /// `nil` when this variable's type has no smart default *of a shape this
    /// branch handles* — an `AnyCancellable` or `Disposable` property, say, which
    /// falls through to plain storage below. An impossible `subject` annotation
    /// is not that case and is rethrown: swallowing it emitted a stored property
    /// with no initializer, and the generated file did not compile.
    /// Whether this requirement keeps `<name>Outputs` / `<name>Events`.
    /// `/// sourcery: skipArgumentRecording` on the requirement or on the
    /// protocol turns it off, the way it turns `<method>Args` off (D13).
    fileprivate var recordsStreamValues: Bool {
        return !variable.isAnnotatedSkipArgumentRecording && !type.isAnnotatedSkipArgumentRecording
    }

    private func smartDefaultValueImplementation() throws -> (getterImplementation: [SourceCode], mockedVariableHandlers: [SourceCode], suppliesHandlerConsultation: Bool)? {
        do {
            return try variable.typeName.smartDefaultValueImplementation(
                isProperty: true,
                mockVariablePrefix: mockedVariableName,
                requestedSubjectKind: variable.requestedSubjectKind,
                recordsStreamValues: recordsStreamValues)
        } catch MockError.unseedableSubject(let typeName, let member) {
            throw MockError.unseedableSubject(typeName: typeName, member: member)
        } catch {
            return nil
        }
    }

    /// The witness: a bare getter body where the requirement has no effects and
    /// no setter, and explicit `get` / `set` blocks otherwise. A bare body
    /// cannot carry `async` or `throws`.
    private func accessor(getter: [SourceCode], setter: [SourceCode]?) -> SourceCode {
        let declaration = "\(isolationDecl)var \(variable.name): \(variable.typeName.declaredName)"
        if let setter = setter {
            return SourceCode(declaration) {[
                SourceCode("get", nested: getter),
                SourceCode("set", nested: setter)
            ]}
        }
        if hasEffects {
            return SourceCode(declaration) {[
                SourceCode("get\(effectsDecl)", nested: getter)
            ]}
        }
        return SourceCode(declaration, nested: getter)
    }

    func mockImpl() throws -> [SourceCode] {
        let mockedVariableImplementation: SourceCode
        let mockedVariableHandlers = TopScope()

        // A typed throw reaches the template as `Variable.throwsTypeName` and
        // has no emission here: bare `throws` does not satisfy `throws(E)`.
        if let throwsTypeName = variable.throwsTypeName {
            throw MockError.typedThrowsUnsupported(
                typeName: type.name,
                member: variable.name,
                errorTypeName: throwsTypeName.name)
        }

        if !variable.isMutable,
            variable.typeName.hasComplexTypeWithSmartDefaultValue(isProperty: true),
            let smartDefaultValueImplementation = try smartDefaultValueImplementation() {

            // The publisher branch reads `<var>GetHandler` inside the construct
            // it returns, at subscribe time — so the read-time consultation here
            // would make the handler decide the stream twice, at two different
            // moments (§2.7). Its accessor cannot carry effects either: the
            // `Deferred` closure is not `async`.
            if smartDefaultValueImplementation.suppliesHandlerConsultation, hasEffects {
                throw MockError.effectfulStreamRequirement(typeName: type.name, member: variable.name)
            }
            var getterImplementation: [SourceCode] = [
                SourceCode("\(MockNaming.getCount(mockedVariableName)) += 1")
            ]
            if !smartDefaultValueImplementation.suppliesHandlerConsultation {
                getterImplementation += [SourceCode("if let handler = \(MockNaming.getHandler(mockedVariableName))") {[
                    SourceCode("return \(effectfulCallDecl)handler()")
                ]}]
            }
            getterImplementation += smartDefaultValueImplementation.getterImplementation
            mockedVariableImplementation = accessor(getter: getterImplementation, setter: nil)
            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getCount(mockedVariableName)): Int = 0"
            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getHandler(mockedVariableName)): (()\(effectsDecl) -> \(variable.typeName.declaredName))? = nil"
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
                    SourceCode("return \(effectfulCallDecl)handler()")
                ]},
                variable.isAnnotatedHandler
                    ? SourceCode("fatalError(\"\(MockNaming.getHandlerExpectedMessage(prefix: mockedVariableName))\")")
                    : SourceCode("return \(MockNaming.store(mockedVariableName))")
            ]

            // The witness declares what the requirement declares: a `{ get }`
            // requirement is get-only on the mock, and `_<var>` is how a test
            // seeds it (§12.2 item 2, D18). P5 emitted a setter for a read-only
            // requirement — uncounted, so `mock.draft = x` compiled and moved
            // nothing — which `kotlin-ksp-mocks` §12.4 asked this side to drop,
            // so that `mock._<var> = value` is the one seed expression on both
            // platforms. `const` and `handler` were already get-only.
            //
            // `<var>SetCount` counts a write to a `{ get set }` requirement, and
            // only that (§2.3). An effectful requirement is get-only too: Swift
            // has no effectful setter, so there is nothing for a mutable form to
            // witness.
            let hasSetter = !hasEffects && variable.isMutable
            // Only a `{ get set }` requirement reaches the setter now, so the
            // count is unconditional in it. `didSet` on a stored property was
            // the old shape, and a stored property cannot count a read.
            var setterImplementation: [SourceCode] = [
                SourceCode("\(MockNaming.setCount(mockedVariableName)) += 1")
            ]
            if !variable.isAnnotatedHandler {
                setterImplementation += [SourceCode("\(MockNaming.store(mockedVariableName)) = newValue")]
            }

            mockedVariableImplementation = accessor(
                getter: getterImplementation,
                setter: hasSetter ? setterImplementation : nil)

            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getCount(mockedVariableName)): Int = 0"
            mockedVariableHandlers += "\(storageIsolationDecl)var \(MockNaming.getHandler(mockedVariableName)): (()\(effectsDecl) -> \(variable.typeName.declaredName))? = nil"
            if hasSetter {
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
