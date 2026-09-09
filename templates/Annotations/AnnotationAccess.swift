import Foundation
import SourceryRuntime

// The only file that reads a `/// sourcery:` key by name. Every other template
// file asks for an `AnnotationRegistry` record instead, and
// `Tests/Checks/run-annotation-checks.sh` (check AC1) fails on a string-literal
// annotation read anywhere outside `templates/Annotations/`.

extension SourceryRuntime.Annotated {

    /// `true` when the declaration carries `annotation`'s canonical name or one
    /// of its aliases.
    func isAnnotated(_ annotation: Annotation) -> Bool {
        return annotationValue(of: annotation) != nil
    }

    /// `true` when the declaration carries any of `annotations` — the shape a
    /// template's filter needs when one template has more than one selector.
    func isAnnotated(any annotations: [Annotation]) -> Bool {
        return annotations.contains { isAnnotated($0) }
    }

    /// Every value carried by `annotation`'s canonical name or by one of its
    /// aliases, de-duplicated and sorted. Sorted rather than declaration-ordered
    /// so a caller taking `.first` gets the same value however the aliases are
    /// listed.
    func annotations(for annotation: Annotation) -> [String] {
        return annotations(for: [annotation])
    }

    func annotations(for annotations: [Annotation]) -> [String] {
        return annotations
            .flatMap { $0.spellings }
            .flatMap { extractAnnotations(named: $0) }
            .removeDuplicates()
            .sorted()
    }

    /// The raw value stored under `annotation`'s canonical name or one of its
    /// aliases, or `nil`.
    private func annotationValue(of annotation: Annotation) -> NSObject? {
        for spelling in annotation.spellings {
            if let value = annotations[spelling] { return value }
        }
        return nil
    }

    private func extractAnnotations(named name: String) -> [String] {
        let value = annotations[name]
        if let values = value as? [String] {
            return values.map { $0.trimmingWhitespace() }
        } else if let single = value as? String {
            return [single.trimmingWhitespace()]
        } else {
            return []
        }
    }
}

extension Annotation {
    /// The canonical name first, then the aliases.
    var spellings: [String] {
        return [name] + aliases
    }
}

private extension Array where Element: Hashable, Element: Comparable {
    func removeDuplicates() -> [Element] {
        return Array(Set(self)).sorted()
    }
}

// MARK: - Near misses

extension AnnotationRegistry {

    /// Compare every `/// sourcery:` key on `types` — and on their members, and
    /// on those members' parameters — against the registry, and answer the ones
    /// that nearly match.
    ///
    /// Sourcery accepts any key and stores it. A key no template asks for is
    /// simply absent from generation, so a misspelled selector produces no mock,
    /// no warning and no error. Comparing against the registry is what turns that
    /// silence into a message.
    ///
    /// Run this over *unfiltered* protocols, before the filter. A protocol whose
    /// selector is misspelled is not in the filtered list, so a scan inside the
    /// generator would never see the one case it exists for. Check AC9 asserts
    /// the ordering at each entry point.
    ///
    /// Deliberately narrow: a key bearing no case-insensitive resemblance to any
    /// registry entry belongs to another template in the same Sourcery run and
    /// draws no response.
    ///
    /// Severity follows `kind`. A misspelled **selector** means the type
    /// generates nothing at all, which is the most damaging silent outcome, so it
    /// fails generation. A misspelled **option** leaves a working mock missing one
    /// behaviour, and an adopter running their own templates in the same pass may
    /// legitimately own `handler`, `init`, `import`, `subject` or `const`, so it
    /// writes one comment line and generation continues.
    ///
    /// That comment is not a log line, and the difference was measured rather
    /// than assumed. A Swift template's stdout is the generated file, and
    /// Sourcery 2.3.0 turns any write to the template's stderr into
    /// `error: <template>: <text>`, aborting the run with exit 3 and writing no
    /// output. So a message that must not fail the build has exactly one place to
    /// go: the file being written.
    static func rejectNearMisses(in types: [SourceryRuntime.`Type`]) throws {
        var failures: [String] = []
        var notes: [String] = []

        func inspect<Keys: Sequence>(_ keys: Keys, on context: String) where Keys.Element == String {
            for key in keys {
                guard let miss = nearMiss(of: key) else { continue }
                switch miss.kind {
                case .templateSelector: failures.append(miss.message(found: key, on: context))
                case .option: notes.append(miss.message(found: key, on: context))
                }
            }
        }

        // Sourcery propagates a declaration's annotations onto everything nested
        // in it, so a key written once on a protocol is present again on each of
        // its methods and again on each of their parameters. Report it where the
        // author wrote it: a member's keys are compared against its parent's, and
        // only the ones it adds are inspected.
        for type in types {
            let typeKeys = Set(type.annotations.keys)
            inspect(typeKeys, on: "`\(type.name)`")
            for variable in type.variables {
                inspect(Set(variable.annotations.keys).subtracting(typeKeys), on: "`\(type.name).\(variable.name)`")
            }
            for method in type.methods {
                let methodKeys = Set(method.annotations.keys)
                inspect(methodKeys.subtracting(typeKeys), on: "`\(type.name).\(method.name)`")
                for parameter in method.parameters {
                    inspect(Set(parameter.annotations.keys).subtracting(methodKeys).subtracting(typeKeys),
                            on: "parameter `\(parameter.name)` of `\(type.name).\(method.name)`")
                }
            }
        }

        for note in notes.removeDuplicates() {
            print("// sourcery-templates: \(note)")
        }
        if !failures.isEmpty {
            throw AnnotationError.unrecognizedNames(failures.removeDuplicates())
        }
    }

    /// The registry entry `key` was probably meant to be, or `nil` when `key` is
    /// a live spelling or resembles nothing the registry knows.
    static func nearMiss(of key: String) -> AnnotationNearMiss? {
        if liveSpellings.contains(key) { return nil }
        let lowercased = key.lowercased()
        if let annotation = liveByLowercasedSpelling[lowercased] {
            return AnnotationNearMiss(canonical: annotation.name, kind: annotation.kind, retiredIn: nil)
        }
        if let retired = retiredByLowercasedSpelling[lowercased] {
            return AnnotationNearMiss(canonical: retired.replacement, kind: retired.kind, retiredIn: retired.retiredIn)
        }
        return nil
    }

    private static let liveSpellings: Set<String> = Set(all.flatMap { $0.spellings })

    private static let liveByLowercasedSpelling: [String: Annotation] = {
        var index: [String: Annotation] = [:]
        for annotation in all {
            for spelling in annotation.spellings {
                index[spelling.lowercased()] = annotation
            }
        }
        return index
    }()

    private static let retiredByLowercasedSpelling: [String: RetiredAnnotation] = {
        var index: [String: RetiredAnnotation] = [:]
        for entry in retired {
            for spelling in [entry.name] + entry.aliases {
                index[spelling.lowercased()] = entry
            }
        }
        return index
    }()
}

struct AnnotationNearMiss {
    let canonical: String
    let kind: Annotation.Kind
    /// The release that retired the spelling, or `nil` when it is a misspelling
    /// of a live one.
    let retiredIn: String?

    /// `context` arrives already formatted, because a parameter's reads
    /// "parameter `id` of `Foo.run(id:)`" and a type's is one name.
    func message(found: String, on context: String) -> String {
        if let retiredIn = retiredIn {
            return "`\(found)` on \(context) was retired in \(retiredIn) — write `\(canonical)`"
        }
        return "`\(found)` on \(context) is not `\(canonical)` — annotation names are matched exactly, including case"
    }
}

enum AnnotationError: Error {
    case unrecognizedNames([String])
}

extension AnnotationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unrecognizedNames(let messages):
            let heading = messages.count == 1
                ? "An annotation selects no template, so its type would generate nothing:"
                : "\(messages.count) annotations select no template, so their types would generate nothing:"
            return ([heading] + messages.map { "  - \($0)" }).joined(separator: "\n")
        }
    }
}

extension AnnotationError: CustomStringConvertible {
    var description: String {
        return errorDescription ?? String(describing: self)
    }
}

extension AnnotationError: CustomDebugStringConvertible {
    var debugDescription: String {
        return errorDescription ?? String(describing: self)
    }
}
