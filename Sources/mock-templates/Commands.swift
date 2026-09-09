import ArgumentParser
import Foundation

/// The `config:` line's description, in one place: `generate` and `imprint`
/// write it, and `validate --template` recomputes it from the caller's
/// current config and fails on a difference. The template is recorded by
/// basename, so a caller naming it by path and one naming it by file produce
/// the same line; the arguments are sorted, so their order in a config does
/// not move it.
func mockTemplatesConfigDescription(template: String, arguments: [String]) -> String {
  let name = URL(fileURLWithPath: template).lastPathComponent
  return "template=\(name) args=\(arguments.sorted().joined(separator: ";"))"
}

/// The options `generate` and `imprint` share: everything the fingerprint
/// records. The tool is policy-free — it hashes the files it is pointed at
/// and knows nothing about who calls it or why; pin policy and source-set
/// derivation live in the calling script.
struct FingerprintOptions: ParsableArguments {
  @Option(help: "A root Sourcery scans — a directory or a single .swift file. Repeatable.")
  var sources: [String] = []

  @Option(help: "The template file; its basename joins the config line.")
  var templates: String

  @Option(
    name: .customLong("args"),
    help: "A generator argument, key=value, passed to the engine verbatim. Repeatable; sorted into the config line."
  )
  var arguments: [String] = []

  @Option(help: "The release tag of the template bundle, recorded on the bundle line.")
  var bundleVersion: String

  @Option(help: "Recorded input paths are relative to this directory. Default: the working directory.")
  var root: String = FileManager.default.currentDirectoryPath

  @Option(help: "The file to write.")
  var output: String

  func validate() throws {
    guard !sources.isEmpty else {
      throw ValidationError("at least one --sources root is required")
    }
  }

  var configDescription: String {
    mockTemplatesConfigDescription(template: templates, arguments: arguments)
  }

  func hashedInputs() throws -> [Fingerprint.Input] {
    // The output is excluded from its own input set (see SourceSet) — a row
    // whose root contains the file it generates stays validatable.
    try SourceSet.enumerate(sources: sources, relativeTo: root, excluding: output).map { path in
      Fingerprint.Input(path: path, hash: try sha256Hex(fileAt: rootedPath(path)))
    }
  }

  func rootedPath(_ relative: String) -> String {
    URL(fileURLWithPath: root).standardizedFileURL.appendingPathComponent(relative).path
  }

  func fingerprint(bodyData: Data) throws -> Fingerprint {
    let description = configDescription
    return Fingerprint(
      bundle: bundleVersion,
      configHash: sha256Hex(Data(description.utf8)),
      configDescription: description,
      inputs: try hashedInputs(),
      bodyHash: sha256Hex(bodyData)
    )
  }

  func write(fingerprint: Fingerprint, body: Data) throws {
    var data = Data(fingerprint.rendered().utf8)
    data.append(body)
    try data.write(to: URL(fileURLWithPath: output), options: .atomic)
    print("mock-templates: \(output) — \(fingerprint.inputs.count) inputs, body sha256:\(fingerprint.bodyHash.prefix(12))…")
  }
}

struct Generate: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Run the generation engine, then imprint the output with its fingerprint."
  )

  @OptionGroup var options: FingerprintOptions

  @Option(help: "The sourcery executable to run.")
  var sourcery: String

  @Flag(help: "Pass --disableCache to sourcery.")
  var disableCache = false

  func run() throws {
    // The scratch file keeps the real file name: Sourcery emits its
    // "Generated using Sourcery" banner only for a .swift output, and the
    // banner is part of the body the fingerprint hashes.
    let outputURL = URL(fileURLWithPath: options.output)
    let scratchDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mock-templates-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    let scratchURL = scratchDirectory.appendingPathComponent(outputURL.lastPathComponent)
    defer { try? FileManager.default.removeItem(at: scratchDirectory) }

    var engineArguments: [String] = []
    for source in options.sources {
      engineArguments += ["--sources", source]
    }
    engineArguments += ["--templates", options.templates, "--output", scratchURL.path, "--quiet"]
    for argument in options.arguments {
      engineArguments += ["--args", argument]
    }
    if disableCache {
      engineArguments.append("--disableCache")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: sourcery)
    process.arguments = engineArguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw RuntimeError("sourcery exited with status \(process.terminationStatus)")
    }

    let body = try Data(contentsOf: scratchURL)
    guard !body.isEmpty else {
      throw RuntimeError("sourcery produced no output at \(scratchURL.path)")
    }
    try options.write(fingerprint: try options.fingerprint(bodyData: body), body: body)
  }
}

struct Imprint: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Re-imprint an existing generated file without regenerating it.",
    discussion: """
      Reads --output, strips its fingerprint block when one is present, and \
      writes it back under a fresh block computed from the current sources. \
      The body is untouched.
      """
  )

  @OptionGroup var options: FingerprintOptions

  func run() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: options.output))
    let body = try Fingerprint.parse(data)?.body ?? data
    try options.write(fingerprint: try options.fingerprint(bodyData: body), body: body)
  }
}

struct Validate: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check a generated file against its fingerprint — no generation engine involved.",
    discussion: """
      Re-hashes every input the block lists, plus the body, and fails on any \
      difference. With --sources, also fails on a .swift file that is present \
      under a root but absent from the block — the case where a file was \
      added after generation. With --template, recomputes the config \
      description from the template and args the caller passes and fails when \
      it differs from the one the block records — the case where the config \
      that owns the file changed and the file was not regenerated.
      """
  )

  @Option(help: "The generated file to check.")
  var file: String

  @Option(help: "Recorded input paths resolve relative to this directory. Default: the working directory.")
  var root: String = FileManager.default.currentDirectoryPath

  @Option(help: "A root the current generation config scans. Repeatable; enables the set check.")
  var sources: [String] = []

  @Option(help: "Fail unless the recorded bundle tag is exactly this.")
  var expectBundle: String?

  @Option(
    help: "The template the current config generates with — a name or a path, recorded by basename. Enables the config check."
  )
  var template: String?

  @Option(
    name: .customLong("args"),
    help: "A generator argument, key=value, as the current config passes it. Repeatable; sorted into the recomputed config line. Needs --template."
  )
  var arguments: [String] = []

  func validate() throws {
    // Args alone cannot build the line — it names the template first — so a
    // caller passing them without one is refused rather than run through the
    // checks that apply when neither flag is given.
    guard template != nil || arguments.isEmpty else {
      throw ValidationError("--args needs --template: the config line names both")
    }
  }

  func run() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: file))
    guard let (fingerprint, body) = try Fingerprint.parse(data) else {
      throw RuntimeError("\(file) carries no fingerprint block — regenerate it")
    }

    var failures: [String] = []

    if let expectBundle, fingerprint.bundle != expectBundle {
      failures.append("bundle: recorded \(fingerprint.bundle), expected \(expectBundle)")
    }

    let expectedConfigHash = sha256Hex(Data(fingerprint.configDescription.utf8))
    if fingerprint.configHash != expectedConfigHash {
      failures.append("config: the hash does not match its own description line")
    }

    if let template {
      let current = mockTemplatesConfigDescription(template: template, arguments: arguments)
      if fingerprint.configDescription != current {
        failures.append(
          "config: the block records \(fingerprint.configDescription), the current config is \(current)")
      }
    }

    if sha256Hex(body) != fingerprint.bodyHash {
      failures.append("body: hash differs — the output was edited after imprinting")
    }

    let rootURL = URL(fileURLWithPath: root).standardizedFileURL
    for input in fingerprint.inputs {
      let path = rootURL.appendingPathComponent(input.path).path
      guard FileManager.default.fileExists(atPath: path) else {
        failures.append("missing: \(input.path)")
        continue
      }
      if try sha256Hex(fileAt: path) != input.hash {
        failures.append("stale: \(input.path) — content differs from the recorded hash")
      }
    }

    if !sources.isEmpty {
      let recorded = Set(fingerprint.inputs.map(\.path))
      for path in try SourceSet.enumerate(
        sources: sources, relativeTo: rootURL.path, excluding: file)
      where !recorded.contains(path) {
        failures.append("unlisted: \(path) — present under a sources root, absent from the fingerprint")
      }
    }

    guard failures.isEmpty else {
      for failure in failures {
        print("mock-templates: \(failure)")
      }
      print("mock-templates: \(file) is stale — regenerate it")
      throw ExitCode.failure
    }
    print("mock-templates: \(file) is current — \(fingerprint.inputs.count) inputs verified, body verified")
  }
}

struct RuntimeError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
