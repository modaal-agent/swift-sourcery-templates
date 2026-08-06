import Foundation
import SourceryRuntime

extension SourceryRuntime.Annotated {
    func annotations(for names: [String]) -> [String] {
        return names
            .flatMap { extractAnnotations(for: $0) }
            .removeDuplicates()
            .sorted()
    }

    private func extractAnnotations(for name: String) -> [String] {
        if let annotations = annotations[caseInsensitive: name] as? [String] {
            return annotations.map { $0.trimmingWhitespace() }
        } else if let annotation = annotations[caseInsensitive: name] as? String {
            return [annotation.trimmingWhitespace()]
        } else {
            return []
        }
    }

    // `get`-only variable requirements in protocols are considered mutable and are mocked using `var` declarations by default.
    // To generate a `let` declaration, annotate with `sourcery: const`.
    var isAnnotatedConst: Bool {
        return annotations[caseInsensitive: "const"] != nil
    }

    // For a 'get'-only variable requirement in the protocol, determine if it should be included in the mock class' initializer list.
    var isAnnotatedInit: Bool {
        precondition(!isAnnotatedInitInternal || !isAnnotatedHandlerInternal, "`isAnnotatedInit` is mutually exclusive with `isAnnotatedHandler`")
        return isAnnotatedInitInternal
    }
    private var isAnnotatedInitInternal: Bool {
        return annotations[caseInsensitive: "init"] != nil
    }

    // Suppresses the `<method>Args` array on a mocked method, or on every method
    // of a protocol when it is declared on the type.
    //
    // A recorded argument lives as long as the mock does. When the argument is
    // the object a churn or leak spec asserts the deallocation of, that retain
    // reads as a leak in the code under test, and this is the opt-out. Call
    // counts and the handler are unaffected.
    var isAnnotatedSkipArgumentRecording: Bool {
        return annotations[caseInsensitive: "skipArgumentRecording"] != nil
    }

    // For a `get`-only variable requirement in the protocol,
    var isAnnotatedHandler: Bool {
        precondition(!isAnnotatedHandlerInternal || !isAnnotatedInitInternal, "`isAnnotatedHandler` is mutually exclusive with `isAnnotatedInit`")
        return isAnnotatedHandlerInternal
    }
    private var isAnnotatedHandlerInternal: Bool {
        return annotations[caseInsensitive: "handler"] != nil
    }
}

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
