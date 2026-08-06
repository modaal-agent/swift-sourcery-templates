import Foundation
import SourceryRuntime

/// Emits the composition **Component** for every protocol annotated
/// `/// sourcery: DuetComponent`.
///
/// The shape it serves: a dependency-injection tree where each level declares an
/// `<X>Dependency` protocol naming exactly what it consumes, and owns an
/// `<X>Component` that forwards each of those members to its parent and holds
/// what is scoped to the level. The forwarders are mechanical — one
/// `var m: T { dependency.m }` per requirement — and this generator writes them.
///
/// ```swift
/// /// sourcery: DuetComponent
/// protocol TimelineDependency: AnyObject {
///   var themeProvider: ThemeProviding { get }
/// }
/// ```
///
/// generates
///
/// ```swift
/// final class TimelineComponent: TimelineDependency {
///     private let dependency: TimelineDependency
///
///     init(dependency: TimelineDependency) {
///         self.dependency = dependency
///     }
///     var themeProvider: ThemeProviding { dependency.themeProvider }
/// }
/// ```
///
/// ### Levels that own something
///
/// A generated type cannot carry a hand-written `lazy var`, so a level that owns
/// objects annotates `DuetComponent, owns`. The emission becomes a non-`final`
/// `<X>ComponentBase`, and the level hand-writes the subclass that holds what it
/// owns:
///
/// ```swift
/// final class MainComponent: MainComponentBase {
///     lazy var feedAudioPlayer: FeedAudioPlaying = FeedAudioPlayer(/* … */)
/// }
/// ```
///
/// Getting `owns` wrong is a compile error, not a silent defect: a `final class`
/// cannot be subclassed, and a stored property cannot be added in an extension.
///
/// ### Annotations
///
/// | annotation | effect |
/// | --- | --- |
/// | `DuetComponent` | generate the Component for this protocol |
/// | `owns` | emit `<X>ComponentBase` (non-final) instead of `<X>Component` |
/// | `componentName = "Foo"` | name the emitted type `Foo` / `FooBase` instead of deriving it |
/// | `componentAccess = "public"` | emit `public`; the default is internal, whatever the protocol's own access |
///
/// The emitted type is internal by default **even when the protocol is public**:
/// a composition Component is consumed by the builders of its own module, and
/// deriving its access from the protocol would widen a module's API surface as a
/// side effect of generating boilerplate.
///
/// ### What it refuses
///
/// A `static` requirement, an `init` requirement, a `subscript` requirement and
/// an `associatedtype` all fail generation with a diagnostic naming the member.
/// None can be discharged by forwarding to a stored instance, so emitting a
/// partial Component would produce a conformance error far from its cause.
enum ComponentGenerator {

    static func generate(for types: [SourceryRuntime.`Type`]) throws -> String {
        let scope = TopScope()
        for type in types.sorted(by: { $0.name < $1.name }) {
            scope += ""
            scope += "// MARK: - \(try componentName(for: type))"
            scope += try component(for: type)
        }
        return scope.indentedSourcecode()
    }
}

// MARK: - Naming

private extension ComponentGenerator {

    /// `TimelineDependency` → `TimelineComponent`, or `TimelineComponentBase`
    /// when the level owns something. A protocol not named `<X>Dependency` keeps
    /// its whole name as the stem, so `Timeline` → `TimelineComponent` too.
    static func componentName(for type: SourceryRuntime.`Type`) throws -> String {
        let suffix = ownsScope(type) ? "ComponentBase" : "Component"
        if let annotated = type.annotations(for: ["componentName"]).first, !annotated.isEmpty {
            return "\(annotated)\(ownsScope(type) ? "Base" : "")"
        }
        let stem = type.name.hasSuffix("Dependency")
            ? String(type.name.dropLast("Dependency".count))
            : type.name
        guard !stem.isEmpty else {
            throw MockError.internalError(message: "Component generator: cannot derive a type name from '\(type.name)' — set `componentName`.")
        }
        return "\(stem)\(suffix)"
    }

    static func ownsScope(_ type: SourceryRuntime.`Type`) -> Bool {
        return type.annotations["owns"] != nil
    }

    /// Internal unless asked otherwise. Returns the modifier with its trailing
    /// space, so it concatenates directly.
    static func accessDecl(_ type: SourceryRuntime.`Type`) -> String {
        guard let requested = type.annotations(for: ["componentAccess"]).first, !requested.isEmpty else { return "" }
        return requested.hasSuffix(" ") ? requested : "\(requested) "
    }
}

// MARK: - Emission

private extension ComponentGenerator {

    static func component(for type: SourceryRuntime.`Type`) throws -> SourceCode {
        try reject(unsupportedMembersOf: type)

        let name = try componentName(for: type)
        let owns = ownsScope(type)
        let access = accessDecl(type)
        let isolated = type.emitsNonisolatedMembers

        // A nonisolated forwarder reads `dependency`, so on an isolated
        // Component with any nonisolated requirement the storage has to leave
        // the actor. This is the same rule the mock generator reaches for its
        // call counters, and it is an unchecked assertion in both places.
        let storageIsolation = (isolated && hasNonisolatedMember(type)) ? "nonisolated(unsafe) " : ""
        // Only the non-final base needs it stated: a `final class` whose only
        // stored property is an immutable `Sendable` is checked-Sendable on its
        // own, and a non-final class cannot be checked at all.
        let sendable = (owns && type.requiresUncheckedSendable) ? ", @unchecked Sendable" : ""

        let declaration = SourceCode("\(access)\(owns ? "" : "final ")class \(name): \(type.name)\(sendable)")
        declaration.isBlockMandatory = true

        // `private` on the fully generated Component: nothing else can reach it.
        // On the base, the hand-written subclass is the reason it exists.
        let storageAccess = owns ? access : "private "
        declaration += "\(storageIsolation)\(storageAccess)let dependency: \(type.name)"
        declaration += ""
        declaration += SourceCode("\(access)init(dependency: \(type.name))") {[
            SourceCode("self.dependency = dependency")
        ]}

        for variable in forwardedVariables(of: type) {
            declaration += forwarder(for: variable, access: access, isolated: isolated)
        }
        for method in forwardedMethods(of: type) {
            declaration += forwarder(for: method, access: access, isolated: isolated)
        }

        if let globalActor = type.globalActorAttributeName {
            return declaration.prefixed("@\(globalActor)\n")
        }
        return declaration
    }

    static func forwarder(for variable: SourceryRuntime.Variable, access: String, isolated: Bool) -> SourceCode {
        let nonisolated = (isolated && variable.isDeclaredNonisolated) ? "nonisolated " : ""
        let head = "\(nonisolated)\(access)var \(variable.name): \(variable.typeName.mockTypeName)"

        // An effectful requirement (`{ get async throws }`) forwards through an
        // effectful getter. The mock template does not support these; forwarding
        // one is a straight pass-through, so the Component does.
        if variable.isAsync || variable.throws {
            let effects = "\(variable.isAsync ? " async" : "")\(variable.throws ? " throws" : "")"
            let call = "\(variable.throws ? "try " : "")\(variable.isAsync ? "await " : "")dependency.\(variable.name)"
            return SourceCode(head) {[
                SourceCode("get\(effects) { \(call) }")
            ]}
        }
        if variable.isMutable {
            return SourceCode(head) {[
                SourceCode("get { dependency.\(variable.name) }"),
                SourceCode("set { dependency.\(variable.name) = newValue }"),
            ]}
        }
        return SourceCode("\(head) { dependency.\(variable.name) }")
    }

    static func forwarder(for method: SourceryRuntime.Method, access: String, isolated: Bool) -> SourceCode {
        let nonisolated = (isolated && method.isDeclaredNonisolated) ? "nonisolated " : ""
        let effects = "\(method.isAsync ? " async" : "")\(method.`throws` ? " throws" : method.`rethrows` ? " rethrows" : "")"
        let returns = method.returnTypeName.isVoid ? "" : " -> \(method.returnTypeName.name)"
        let parameters = method.parameters.map { $0.parametersDecl }.joined(separator: ", ")
        let arguments = method.parameters.map { parameter -> String in
            let reference = parameter.`inout` ? "&" : ""
            guard let label = parameter.argumentLabel else { return "\(reference)\(parameter.name)" }
            return "\(label): \(reference)\(parameter.name)"
        }.joined(separator: ", ")
        let call = "\(method.`throws` || method.`rethrows` ? "try " : "")\(method.isAsync ? "await " : "")"

        return SourceCode("\(nonisolated)\(access)func \(method.shortName)(\(parameters))\(effects)\(returns)") {[
            SourceCode("\(call)dependency.\(method.callName)(\(arguments))")
        ]}
    }
}

// MARK: - Members

private extension ComponentGenerator {

    /// Requirements this Component must satisfy, inherited ones included:
    /// `allVariables` / `allMethods` resolve the protocol's whole conformance
    /// surface, which is what makes a refining `<X>Dependency` work.
    static func forwardedVariables(of type: SourceryRuntime.`Type`) -> [SourceryRuntime.Variable] {
        var seen = Set<String>()
        return type.allVariables
            .filter { !$0.isStatic && $0.definedInType?.isExtension != true }
            .sorted { $0.name < $1.name }
            .filter { seen.insert($0.name).inserted }
    }

    static func forwardedMethods(of type: SourceryRuntime.`Type`) -> [SourceryRuntime.Method] {
        var seen = Set<String>()
        return type.allMethods
            .filter { !$0.isStatic && !$0.isInitializer && $0.definedInType?.isExtension != true }
            .sorted { $0.selectorName < $1.selectorName }
            .filter { seen.insert($0.selectorName).inserted }
    }

    static func hasNonisolatedMember(_ type: SourceryRuntime.`Type`) -> Bool {
        return type.allVariables.contains { $0.isDeclaredNonisolated }
            || type.allMethods.contains { $0.isDeclaredNonisolated }
    }

    /// Requirements a forwarding Component cannot discharge. Each fails
    /// generation rather than emitting a class that will not conform.
    static func reject(unsupportedMembersOf type: SourceryRuntime.`Type`) throws {
        func refuse(_ what: String, _ member: String) throws -> Never {
            throw MockError.internalError(
                message: "Component generator: \(type.name) declares \(what) '\(member)'. A Component forwards to a stored instance, which cannot satisfy it — remove it from the Dependency protocol, or drop the `DuetComponent` annotation and write the Component by hand.")
        }
        // Backticked: `Protocol` also names Foundation's Objective-C protocol
        // metatype, and the unquoted form does not resolve inside a template.
        if let associated = (type as? SourceryRuntime.`Protocol`)?.associatedTypes.keys.sorted().first {
            try refuse("the associated type", associated)
        }
        if let staticVariable = type.allVariables.first(where: { $0.isStatic }) {
            try refuse("the static requirement", staticVariable.name)
        }
        // Before the static check: Sourcery reports an initializer requirement
        // as static too, and "declares the static requirement 'init(tag:)'" is
        // not the sentence that tells an author what to do.
        if let initializer = type.allMethods.first(where: { $0.isInitializer }) {
            try refuse("the initializer requirement", initializer.selectorName)
        }
        if let staticMethod = type.allMethods.first(where: { $0.isStatic }) {
            try refuse("the static requirement", staticMethod.selectorName)
        }
        if let subscriptRequirement = type.allSubscripts.first {
            let parameters = subscriptRequirement.parameters.map { $0.typeName.name }.joined(separator: ", ")
            try refuse("the subscript requirement", "subscript(\(parameters)) -> \(subscriptRequirement.returnTypeName.name)")
        }
    }
}
