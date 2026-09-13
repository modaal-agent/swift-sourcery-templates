import Foundation
import SourceryRuntime

/// `// sourcery: if = "<condition>"` on a protocol, a method or a property, turned into the `#if` its
/// generated code sits inside, and into the imports those conditions guard (spec 006 §8.4, §9.3,
/// §10.2).
///
/// The value is the text after `#if` in the directive the annotation stands for. Sourcery 2.3.0 visits
/// every clause of an `#if` and records no condition, so a declaration inside one that carries no `if`
/// is generated with no condition.
///
/// All three entry points include this file. `TypeErase.swifttemplate` includes nothing under
/// `Mocks/`, so nothing here names `SourceCode`.
enum CompilationConditions {

    // MARK: - Directives

    static func opening(_ condition: String) -> String {
        return "#if \(condition)"
    }

    static let closing = "#endif"

    /// The condition `line` opens, or `nil` when `line` is not an `#if` directive.
    static func condition(openedBy line: String) -> String? {
        let prefix = opening("")
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    // MARK: - Conditions

    /// The condition around a whole generated type, or `nil`.
    static func condition(of type: SourceryRuntime.`Type`) -> String? {
        return conjunction(of: type)
    }

    /// The condition around a method's generated lines, or `nil`.
    ///
    /// Sourcery folds the declarations of one signature into one `allMethods` entry and keeps the first
    /// one's annotations. A member declared in two clauses of an `#if` is generated when either clause
    /// is compiled, so the conditions of every declaration folded into it are joined with `||`, and one
    /// of them with no `if` leaves the member with none.
    static func condition(of method: SourceryRuntime.Method) -> String? {
        return disjunction(of: foldedDeclarations(of: method).map { conjunction(of: $0) })
    }

    /// The condition around a property's generated lines, or `nil`. Folded as a method is.
    static func condition(of variable: SourceryRuntime.Variable) -> String? {
        return disjunction(of: foldedDeclarations(of: variable).map { conjunction(of: $0) })
    }

    /// `true` when two properties of one generated type share a name and each is generated inside a
    /// condition of its own that differs from the other's as text: `var mode: Int` under one clause of
    /// an `#if` and `var mode: String` under another. Both are generated, with the same member names.
    static func keepsBoth(_ lhs: SourceryRuntime.Variable, _ rhs: SourceryRuntime.Variable) -> Bool {
        guard let lhsCondition = condition(of: lhs), let rhsCondition = condition(of: rhs) else { return false }
        return lhsCondition != rhsCondition
    }

    /// Several `if` values on one declaration, each in parentheses, joined with `&&`. The values are
    /// read sorted, so the order of the source lines does not change the text.
    private static func conjunction(of declaration: SourceryRuntime.Annotated) -> String? {
        let values = declaration.annotations(for: AnnotationRegistry.ifCondition).filter { !$0.isEmpty }
        switch values.count {
        case 0: return nil
        case 1: return values[0]
        default: return values.map { "(\($0))" }.joined(separator: " && ")
        }
    }

    private static func disjunction(of conditions: [String?]) -> String? {
        var distinct: [String] = []
        for condition in conditions {
            guard let condition = condition else { return nil }
            if !distinct.contains(condition) { distinct.append(condition) }
        }
        switch distinct.count {
        case 0: return nil
        case 1: return distinct[0]
        default: return distinct.sorted().map { "(\($0))" }.joined(separator: " || ") }
    }

    /// Every declaration of the protocol that declares `method` which Sourcery folds into it, `method`
    /// included. The test is Sourcery's `Type.uniqueMethodFilter` (`SourceryRuntime/Sources/macOS/AST/Type.swift:135-137`
    /// at tag 2.3.0). A declaration in an extension provides a default and is not generated.
    private static func foldedDeclarations(of method: SourceryRuntime.Method) -> [SourceryRuntime.Method] {
        let folded = method.definedInType?.rawMethods.filter {
            $0.definedInType?.isExtension != true
                && $0.name == method.name
                && $0.isStatic == method.isStatic
                && $0.isClass == method.isClass
                && $0.actualReturnTypeName.name == method.actualReturnTypeName.name
        } ?? []
        return folded.isEmpty ? [method] : folded
    }

    /// As for a method, with Sourcery's `Type.uniqueVariableFilter` (`Type.swift:107-109`).
    private static func foldedDeclarations(of variable: SourceryRuntime.Variable) -> [SourceryRuntime.Variable] {
        let folded = variable.definedInType?.rawVariables.filter {
            $0.definedInType?.isExtension != true
                && $0.name == variable.name
                && $0.isStatic == variable.isStatic
                && $0.typeName.name == variable.typeName.name
        } ?? []
        return folded.isEmpty ? [variable] : folded
    }

    // MARK: - Imports

    /// The text after `//` that makes an `args.import` or `args.testable` item manual.
    static let manualImportMarker = "if canImport"

    /// One `args.import` or `args.testable` item.
    struct ImportItem {
        /// The item as configured.
        let text: String
        /// The text before the first `//`, trimmed.
        let module: String
        /// `true` for `<module> // if canImport`.
        let isManual: Bool

        init(_ text: String) {
            self.text = text
            if let comment = text.range(of: "//") {
                module = text[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
                isManual = text[comment.upperBound...].trimmingCharacters(in: .whitespaces) == CompilationConditions.manualImportMarker
            } else {
                module = text.trimmingCharacters(in: .whitespaces)
                isManual = false
            }
        }
    }

    /// The generated file's import lines: each `args.import` item as `import`, then each `args.testable`
    /// item as `@testable import`, each list sorted by module.
    ///
    /// An item that is manual, or whose module a `canImport(<M>)` term of an `if` value on `types` or on
    /// their generated members names, is emitted once per list as `#if canImport(<M>)`, the import, and
    /// `#endif`. Every other item is emitted with its full text, as 0.9.0 emits it. A module such a term
    /// names that neither list holds is added to `args.import`'s lines, guarded.
    static func importLines(imports: [String], testable: [String], types: [SourceryRuntime.`Type`]) -> [String] {
        let guardedModules = Set(types.flatMap { importedModules(of: $0) })
        let testableItems = testable.map { ImportItem($0) }
        var importItems = imports.map { ImportItem($0) }
        let listed = Set((importItems + testableItems).map { $0.module })
        importItems += guardedModules.subtracting(listed).map { ImportItem($0) }
        return importLines(importItems, keyword: "import", guardedModules: guardedModules)
            + importLines(testableItems, keyword: "@testable import", guardedModules: guardedModules)
    }

    /// The modules a `canImport(<M>)` term names, negated or not, in an `if` value on `type` or on a
    /// member generated for it.
    static func importedModules(of type: SourceryRuntime.`Type`) -> [String] {
        var declarations: [SourceryRuntime.Annotated] = [type]
        for method in type.allMethods where method.definedInType?.isExtension != true {
            declarations += foldedDeclarations(of: method) as [SourceryRuntime.Annotated]
        }
        for variable in type.allVariables where variable.definedInType?.isExtension != true {
            declarations += foldedDeclarations(of: variable) as [SourceryRuntime.Annotated]
        }
        return declarations
            .flatMap { $0.annotations(for: AnnotationRegistry.ifCondition) }
            .flatMap { modules(namedIn: $0) }
    }

    /// `<M>` of each `canImport(<M>` in `condition`, running to the first `,`, `)` or space.
    static func modules(namedIn condition: String) -> [String] {
        let term = "canImport("
        var modules: [String] = []
        var rest = Substring(condition)
        while let found = rest.range(of: term) {
            rest = rest[found.upperBound...]
            let module = rest.drop { $0 == " " }.prefix { $0 != "," && $0 != ")" && $0 != " " }
            if !module.isEmpty { modules.append(String(module)) }
        }
        return modules
    }

    private static func importLines(_ items: [ImportItem], keyword: String, guardedModules: Set<String>) -> [String] {
        var guardedEmitted = Set<String>()
        var lines: [String] = []
        for item in items.sorted(by: { ($0.module, $0.text) < ($1.module, $1.text) }) {
            guard item.isManual || guardedModules.contains(item.module) else {
                lines.append("\(keyword) \(item.text)")
                continue
            }
            guard guardedEmitted.insert(item.module).inserted else { continue }
            lines += [opening("canImport(\(item.module))"), "\(keyword) \(item.module)", closing]
        }
        return lines
    }
}
