import Foundation
import SourceryRuntime

/// Represents source code construct:
/// line
/// or
/// line {
///     $(nested)
/// }
class SourceCode {
    let line: String
    var nested: [SourceCode]
    var isBlockMandatory: Bool = false // if `true`, always output curly braces after the line, even if nested is empty, e.g., empty class/function declaration.

    init(_ line: String, nested: [SourceCode] = []) {
        self.line = line
        self.nested = nested
    }
    convenience init(_ line: String, nested: () -> [SourceCode]) {
        self.init(line, nested: nested())
    }

    func nest(_ source: SourceCode) {
        nested.append(source)
    }

    func indentedSourcecode(_ level: Int = 0) -> String {
        guard !line.isEmpty else {
            assert(nested.isEmpty)
            return ""
        }
        let indent = String(repeating: " ", count: level * 4)
        var result = "\(indent)\(line)"
        let nestedCode = nested.map { $0.indentedSourcecode(level + 1) }.joined(separator: "\n")
        if !nestedCode.isEmpty {
            if !line.contains("{") { // as in, e.g., "return AnyObserver { [weak self] event in"
                result += " {"
            }
            result += "\n\(nestedCode)\n\(indent)}"
        } else if isBlockMandatory {
            result += " {\n\(indent)}"
        }
        return result
    }
}

extension SourceCode {
    /// A copy of this construct with `prefix` prepended to its first line, used
    /// to attach declaration modifiers (e.g. `nonisolated(unsafe) `) to code the
    /// generator has already assembled.
    func prefixed(_ prefix: String) -> SourceCode {
        guard !prefix.isEmpty, !line.isEmpty else { return self }
        let copy = SourceCode("\(prefix)\(line)", nested: nested)
        copy.isBlockMandatory = isBlockMandatory
        return copy
    }
}

extension Array where Element == SourceCode {
    func isolated(_ prefix: String) -> [SourceCode] {
        return map { $0.prefixed(prefix) }
    }
}

class TopScope {
    var nested: [SourceCode] = []

    func nest(_ source: SourceCode) {
        nested.append(source)
    }

    func indentedSourcecode() -> String {
        return nested.map { $0.indentedSourcecode(0) }.joined(separator: "\n")
    }
}

protocol SourceAppendable {
    func nest(_ source: SourceCode)
}
extension SourceCode: SourceAppendable {}
extension TopScope: SourceAppendable {}
extension SourceAppendable {
    @discardableResult
    func nest(_ line: String) -> SourceCode {
        let sourceLine = SourceCode(line)
        nest(sourceLine)
        return sourceLine
    }

    func nest(contentsOf array: [SourceCode]) {
        array.forEach { nest($0) }
    }

    func nest(contentsOf array: [String]) {
        array.forEach { nest($0) }
    }

    static func +=(_ lhs: Self, _ rhs: SourceCode) {
        lhs.nest(rhs)
    }
    static func +=(_ lhs: Self, _ rhs: [SourceCode]) {
        lhs.nest(contentsOf: rhs)
    }

    @discardableResult
    static func +=(_ lhs: Self, _ line: String) -> SourceCode {
        return lhs.nest(line)
    }

    static func +=(_ lhs: Self, _ lines: [String]) {
        lhs.nest(contentsOf: lines)
    }
}
