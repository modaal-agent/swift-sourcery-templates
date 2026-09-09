import Foundation
import SourceryRuntime

struct GenericTypeInfo {
    let genericType: String // The generic type name, e.g. "S"
    let constraints: Set<String> // Potentially, a constraint on the genericType's subtype, e.g., "S.Iterator.Element: Object"
}

extension SourceryRuntime.Annotated {
    func annotatedAssociatedTypes() -> [GenericTypeInfo] {
        return extractAnnotatedGenericTypes(for: [AnnotationRegistry.associatedType])
    }
    func annotatedGenericTypes() -> [GenericTypeInfo] {
        return extractAnnotatedGenericTypes(for: [AnnotationRegistry.genericType])
    }

    // Each element in `names` might contain several declarations, e.g., "S: Sequence, S: Annotable, S.Iterator.Element: Object"
    private func extractAnnotatedGenericTypes(for names: [Annotation]) -> [GenericTypeInfo] {
        return annotations(for: names)
            .flatMap {
                return $0.commaSeparated().map { constraint in
                    let trimmed = constraint.trimmingWhitespace()
                    let split = trimmed.colonSeparated()
                    let associatedType = String(split[0].split(separator: ".", maxSplits: 1)[0]) // In case it's from the generic constraint of the form "S.Iterator.Element: Object"
                    let constraints: [String] = split.count == 2 ? [trimmed] : [] // This will hold the original value.
                    return GenericTypeInfo(genericType: associatedType, constraints: Set(constraints))
                }
            }
            .merged()
    }
}

extension Collection where Element == GenericTypeInfo {
    // Merge elements with the same `genericType` value, combining `constraints` of merged elements.
    func merged() -> [GenericTypeInfo] {
        return reduce(into: []) { (partialResult: inout [GenericTypeInfo], element: GenericTypeInfo) in
            if let index = partialResult.firstIndex(where: { $0.genericType == element.genericType }) {
                partialResult[index] = GenericTypeInfo(genericType: element.genericType, constraints: partialResult[index].constraints.union(element.constraints))
            } else {
                partialResult.append(element)
            }
        }
    }
}
