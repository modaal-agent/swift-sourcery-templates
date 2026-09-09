import Foundation

// The one place an annotation verb is named.
//
// Every template read routes through a record here, `Scripts/render-annotations.sh`
// renders these records into every document that documents them, and
// `Tests/Checks/run-annotation-checks.sh` fails when a template reads a verb no
// record declares, when a record no template reads survives, or when a rendered
// block is stale.
//
// The three entry points `includeFile` this file, so it is inlined into the same
// compilation unit the rest of the template already shares. It is not loaded at
// generation time and there is no data file to locate. It imports Foundation and
// nothing else — `Scripts/render-annotations.sh` parses it as text with `awk`,
// because the push that most needs the rendition check is a `README.md`-only push,
// which runs on a runner with no Swift toolchain.
//
// THE RECORD SHAPE IS THAT PARSER'S CONTRACT. Each record opens with a line
// matching `^    static let [a-zA-Z]+ = Annotation\($`, carries exactly the six
// field lines below in order, each matching its own pattern, and closes with
// `^    \)$`. Check AC5 asserts it, so the parser cannot skip a record or misread
// a field without a check going red.
//
// A name is matched exactly, including case. A spelling that differs only in
// case is a near-miss, and `rejectNearMisses` in `AnnotationAccess.swift`
// answers it.

struct Annotation {
    /// The canonical spelling, and the only one any rendered document shows.
    let name: String
    /// Spellings that still match. Documented nowhere: rendering one would make
    /// it a second canonical form with no way back (check AC8).
    let aliases: [String]
    let kind: Kind
    /// The declaration an author writes it on, as the rendered table's second column.
    let target: String
    /// What it does, as the rendered table's third column.
    let effect: String
    /// An example right-hand side, rendered as `name = "hint"`, or `nil` for a
    /// verb that carries no value.
    let valueHint: String?

    enum Kind {
        /// An UpperCamelCase noun naming what gets generated. It decides whether
        /// a template processes a type at all.
        case templateSelector
        /// lowerCamelCase. It modifies how a selected type is generated.
        case option
    }
}

/// A verb that shipped and no longer matches. Deleting one outright is silent:
/// Sourcery accepts any `/// sourcery: X`, so a template that stops asking drops
/// a mock, a `let`, an initializer entry or a Component without a word. A record
/// here turns that into a message naming the replacement.
struct RetiredAnnotation {
    let name: String
    let aliases: [String]
    let kind: Annotation.Kind
    let retiredIn: String
    let replacement: String
}

enum AnnotationRegistry {

    // MARK: - Template selectors

    static let protocolMock = Annotation(
        name: "ProtocolMock",
        aliases: ["CreateMock", "Mock", "MockProtocol"],
        kind: .templateSelector,
        target: "Protocol / extension",
        effect: "Generate the mock class",
        valueHint: nil
    )

    static let objcProtocolMock = Annotation(
        name: "ObjcProtocolMock",
        aliases: ["ObjcProtocol"],
        kind: .templateSelector,
        target: "Protocol / extension",
        effect: "Generate the mock class with an `NSObject` superclass. A protocol refining `NSObjectProtocol` gets one without the annotation",
        valueHint: nil
    )

    static let typeErasure = Annotation(
        name: "TypeErasure",
        aliases: ["TypeErase"],
        kind: .templateSelector,
        target: "Protocol",
        effect: "Generate the type-erasing wrapper",
        valueHint: nil
    )

    static let duetComponent = Annotation(
        name: "DuetComponent",
        aliases: [],
        kind: .templateSelector,
        target: "Protocol",
        effect: "Generate the forwarding Component class",
        valueHint: nil
    )

    // MARK: - Options

    static let associatedType = Annotation(
        name: "associatedType",
        aliases: ["associatedTypes"],
        kind: .option,
        target: "Protocol",
        effect: "Associated type for the type erasure",
        valueHint: "T: Constraint"
    )

    static let genericType = Annotation(
        name: "genericType",
        aliases: ["genericTypes"],
        kind: .option,
        target: "Method",
        effect: "Generic type parameter",
        valueHint: "T: Constraint"
    )

    static let annotatedGenericTypes = Annotation(
        name: "annotatedGenericTypes",
        aliases: ["annotatedGenericType", "genericTypePlaceholder", "genericTypesPlaceholder"],
        kind: .option,
        target: "Parameter",
        effect: "Generic placeholder marker",
        valueHint: "{T}"
    )

    static let methodName = Annotation(
        name: "methodName",
        aliases: [],
        kind: .option,
        target: "Method",
        effect: "Override the mock variable name",
        valueHint: "customName"
    )

    static let const = Annotation(
        name: "const",
        aliases: [],
        kind: .option,
        target: "Variable",
        effect: "Use `let` in the mock",
        valueHint: nil
    )

    static let initVariable = Annotation(
        name: "init",
        aliases: [],
        kind: .option,
        target: "Variable",
        effect: "Include in the mock initializer",
        valueHint: nil
    )

    static let handler = Annotation(
        name: "handler",
        aliases: [],
        kind: .option,
        target: "Variable",
        effect: "Generate the handler closure",
        valueHint: nil
    )

    static let importModule = Annotation(
        name: "import",
        aliases: [],
        kind: .option,
        target: "Protocol",
        effect: "Add an `import` to the output",
        valueHint: "Module"
    )

    static let globalActor = Annotation(
        name: "globalActor",
        aliases: [],
        kind: .option,
        target: "Protocol",
        effect: "Declare the mock's global actor when the attribute name does not end in `Actor`",
        valueHint: "MyIsolation"
    )

    static let uncheckedSendable = Annotation(
        name: "uncheckedSendable",
        aliases: [],
        kind: .option,
        target: "Protocol",
        effect: "Force `@unchecked Sendable` on the mock when the `Sendable` refinement is not visible to Sourcery",
        valueHint: nil
    )

    static let subject = Annotation(
        name: "subject",
        aliases: [],
        kind: .option,
        target: "Variable / method",
        effect: "Choose the subject backing an `AnyPublisher` member — `CurrentValue` or `Passthrough`",
        valueHint: "CurrentValue"
    )

    static let skipArgumentRecording = Annotation(
        name: "skipArgumentRecording",
        aliases: [],
        kind: .option,
        target: "Protocol / method",
        effect: "Do not generate `<method>Args`; call counting and the handler are unaffected",
        valueHint: nil
    )

    static let owns = Annotation(
        name: "owns",
        aliases: [],
        kind: .option,
        target: "Protocol",
        effect: "Emit `<X>ComponentBase` (non-final) for a hand-written subclass that holds what the level owns",
        valueHint: nil
    )

    static let componentName = Annotation(
        name: "componentName",
        aliases: [],
        kind: .option,
        target: "Protocol",
        effect: "Name the emitted Component `Foo` instead of deriving it from the protocol",
        valueHint: "Foo"
    )

    static let componentAccess = Annotation(
        name: "componentAccess",
        aliases: [],
        kind: .option,
        target: "Protocol",
        effect: "Emit a `public` Component; the default is internal",
        valueHint: "public"
    )

    // MARK: - Collections

    /// Every record, in rendering order. Check AC2 fails when a record declared
    /// above is missing here, because the near-miss scan reads this list.
    static let all: [Annotation] = [
        protocolMock,
        objcProtocolMock,
        typeErasure,
        duetComponent,
        associatedType,
        genericType,
        annotatedGenericTypes,
        methodName,
        const,
        initVariable,
        handler,
        importModule,
        globalActor,
        uncheckedSendable,
        subject,
        skipArgumentRecording,
        owns,
        componentName,
        componentAccess,
    ]

    /// The selectors `Mocks.swifttemplate` filters on. Both name the same
    /// template, so the filter is a union and carrying both on one protocol is
    /// not an error: `isObjcProtocol` is a separate question asked of the type.
    static let mockSelectors: [Annotation] = [protocolMock, objcProtocolMock]

    /// Emptied two minor releases after an entry is added. Check AC4 fails when
    /// a name appears here and in `all`.
    static let retired: [RetiredAnnotation] = []
}
