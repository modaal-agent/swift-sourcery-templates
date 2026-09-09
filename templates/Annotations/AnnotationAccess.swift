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
            .flatMap { annotation in
                annotation.spellings.flatMap { extractAnnotations(named: $0, matching: annotation.matching) }
            }
            .removeDuplicates()
            .sorted()
    }

    /// The raw value stored under `annotation`'s canonical name or one of its
    /// aliases, or `nil`.
    private func annotationValue(of annotation: Annotation) -> NSObject? {
        for spelling in annotation.spellings {
            switch annotation.matching {
            case .exact:
                if let value = annotations[spelling] { return value }
            case .caseInsensitive:
                if let value = annotations[caseInsensitive: spelling] { return value }
            }
        }
        return nil
    }

    private func extractAnnotations(named name: String, matching: Annotation.Matching) -> [String] {
        let value: NSObject?
        switch matching {
        case .exact: value = annotations[name]
        case .caseInsensitive: value = annotations[caseInsensitive: name]
        }
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

// The one case-insensitive lookup. `templates/Utility/Annotations.swift` and
// `templates/Mocks/SourceryRuntimeExtensions.swift` each carried a copy of this
// under a different argument label.
private extension Dictionary where Key == String {
    subscript(caseInsensitive key: Key) -> Value? {
        return first { $0.0.lowercased() == key.lowercased() }?.value
    }
}

private extension Array where Element: Hashable, Element: Comparable {
    func removeDuplicates() -> [Element] {
        return Array(Set(self)).sorted()
    }
}
