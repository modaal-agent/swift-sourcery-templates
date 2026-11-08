import ArgumentParser
import Foundation

/// `print`: what SourcerySwiftCodegenPlugin generates for one target, written to
/// stdout, with nothing compiled and no file of the project edited. Every line it
/// reports on stderr starts `mock-templates: `, and it exits 1 on each of them
/// except the sandbox retry.
struct PrintCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "print",
    abstract: "Print what SourcerySwiftCodegenPlugin generates for one target, without compiling the target.",
    discussion: """
      Run it from the directory holding Package.swift, or from the one holding \
      the .xcodeproj or .xcworkspace. With protocol names it prints each \
      protocol's `// MARK: - <Protocol>` block of the generated files; with \
      none, every generated file of the target after a `// <path>` line.

      SwiftPM: `swift build --target <target> --print-manifest-job-graph` plans \
      the build, which runs the plugin's prebuild command and compiles nothing, \
      and the files are read from the build directory's plugins/outputs. A \
      package whose platforms rule out the host is planned for the iOS \
      simulator.

      Xcode: re-runs the Sourcery engine on the configs the plugin synthesized \
      at the target's last build, with `output:` pointed at \
      <DerivedData>/Build/Intermediates.noindex/PrintMocks. Needs one earlier \
      build of the target in that derived data. --derived-data, or a \
      .xcodeproj or .xcworkspace in the working directory, selects this lane.
      """
  )

  @Argument(help: "The target that applies the plugin and carries the config: the test target, for mocks.")
  var target: String

  @Argument(help: "A protocol whose mock to print. With none, every generated file of the target.")
  var protocols: [String] = []

  @Option(help: "SwiftPM: the build directory, when it is not .build.")
  var scratchPath: String?

  @Flag(
    help: """
      SwiftPM: add --disable-sandbox to the first plan. Without it, a plan that fails because SwiftPM \
      could not start its sandbox inside another sandbox is run again with the flag.
      """
  )
  var disableSandbox = false

  @Option(help: "Xcode: the derived data directory to read. Selects the Xcode lane.")
  var derivedData: String?

  @Option(help: "Xcode: where to look for the derived data. Default: ~/Library/Developer/Xcode/DerivedData.")
  var derivedDataRoot: String?

  @Option(help: "Xcode: the project directory, when it is not the one holding the .xcodeproj.")
  var project: String?

  @Option(
    help: """
      Xcode: the sourcery executable, when it is found neither beside the templates the configs name, \
      nor beside this binary in an artifact bundle, nor under <DerivedData>/SourcePackages.
      """
  )
  var engine: String?

  func run() throws {
    let here = FileManager.default.currentDirectoryPath
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: here)) ?? []
    if derivedData != nil || entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
      try xcode()
    } else if entries.contains("Package.swift") {
      try spm()
    } else {
      throw fail("run from the directory holding Package.swift or the .xcodeproj")
    }
  }

  // ── printing ──────────────────────────────────────────────────────

  func printGenerated(_ files: [String]) throws {
    guard !files.isEmpty else {
      throw fail(
        "\(target) generated no file — does it apply SourcerySwiftCodegenPlugin and carry a *.sourcery*.yml config?")
    }
    if protocols.isEmpty {
      for file in files {
        writeOut("// \(file)\n")
        writeOut(try Data(contentsOf: URL(fileURLWithPath: file)))
        writeOut("\n")
      }
      return
    }
    var lines: [Substring] = []
    for file in files {
      let text = try String(contentsOfFile: file, encoding: .utf8)
      var fileLines = text.split(separator: "\n", omittingEmptySubsequences: false)
      if text.hasSuffix("\n") { fileLines.removeLast() }
      lines += fileLines
    }
    var missing = 0
    for name in protocols {
      // A mock is its `// MARK: - <Protocol>` line through the first `}` at column 0.
      guard let start = lines.firstIndex(where: { $0 == "// MARK: - \(name)" }) else {
        writeOut("// \(name): no mock generated for \(target)\n")
        missing += 1
        continue
      }
      let end = lines[start...].firstIndex(where: { $0.hasPrefix("}") }) ?? lines.index(before: lines.endIndex)
      writeOut(lines[start...end].joined(separator: "\n") + "\n\n")
    }
    if missing > 0 {
      throw fail("\(missing) of \(protocols.count) protocols have no mock in \(target)'s generated files")
    }
  }

  // ── SwiftPM ───────────────────────────────────────────────────────

  func spm() throws {
    let build = scratchPath ?? ".build"
    let scratch = scratchPath.map { ["--scratch-path", $0] } ?? []
    var sandbox = disableSandbox ? ["--disable-sandbox"] : []
    var err = ""

    // Plans the build, keeping SwiftPM's stderr in memory: an outer sandbox can deny writes to the
    // per-user temporary directory a file would go to. SwiftPM cannot start its own sandbox inside
    // another one: it says `sandbox_apply: Operation not permitted` where it compiles the manifest,
    // and `Plugin ended with exit code 71` where the manifest is already in its cache and the first
    // sandbox it starts is the plugin's. That plan is run again with --disable-sandbox.
    func plan(_ extra: [String]) throws -> Bool {
      let result = try stderrOf(
        ["swift", "build", "--target", target, "--print-manifest-job-graph"] + scratch + sandbox + extra)
      err = result.stderr
      if result.status == 0 { return true }
      guard err.contains("sandbox_apply: Operation not permitted") || err.contains("Plugin ended with exit code 71")
      else { return false }
      guard sandbox.isEmpty else { return false }
      note("SwiftPM could not start its sandbox; planning again with --disable-sandbox")
      sandbox = ["--disable-sandbox"]
      return try plan(extra)
    }

    if try !plan([]) {
      // A package declaring no macOS platform cannot be planned for the host once it depends on the
      // plugin, which requires macOS 13. The simulator plan runs the same prebuild command.
      if err.contains("depends on the product 'SourcerySwiftCodegenPlugin' which requires macos") {
        let sdk = try stdoutOf(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).stdout
        if try !plan(["--triple", "\(hostArchitecture)-apple-ios-simulator", "--sdk", sdk]) {
          writeErr(err.hasSuffix("\n") ? err : err + "\n")
          throw fail("planning \(target) for the iOS simulator failed")
        }
      } else {
        writeErr(err.hasSuffix("\n") ? err : err + "\n")
        throw fail("planning \(target) failed")
      }
    }
    // The plugin warns when the package is not in a git repository; every other warning is passed on.
    for line in err.split(separator: "\n") where line.contains("warning:") && !line.contains("Error running git command") {
      writeErr(line + "\n")
    }

    let outputs = "\(build)/plugins/outputs"
    let marker = "/\(target)/destination/SourcerySwiftCodegenPlugin/.generatedFiles/"
    let files = regularFiles(under: outputs).filter { path in
      path.contains(marker) && path.hasSuffix(".generated.swift")
    }
    try printGenerated(files.sorted())
  }

  // ── Xcode ─────────────────────────────────────────────────────────

  var defaultDerivedDataRoot: String {
    derivedDataRoot ?? NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
  }

  /// The `.sourceryConfigs` directory the plugin wrote for the target most recently: in
  /// --derived-data when it is given, otherwise in each derived data directory whose workspace
  /// sits under the working directory.
  func synthesizedConfigs() -> String? {
    var derivedDataDirectories: [String] = []
    if let derivedData {
      derivedDataDirectories = [derivedData]
    } else if let here = physicalPath(FileManager.default.currentDirectoryPath) {
      let root = defaultDerivedDataRoot
      let children = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).sorted()
      for child in children {
        let directory = "\(root)/\(child)"
        guard let workspace = workspacePath(derivedData: directory),
          let workspaceDirectory = physicalPath((workspace as NSString).deletingLastPathComponent)
        else { continue }
        if "\(workspaceDirectory)/".hasPrefix("\(here)/") {
          derivedDataDirectories.append(directory)
        }
      }
    }
    let suffix = "/\(target)/SourcerySwiftCodegenPlugin/.sourceryConfigs"
    var found: [(modified: Date, path: String)] = []
    for directory in derivedDataDirectories {
      for path in directories(under: "\(directory)/Build/Intermediates.noindex/BuildToolPluginIntermediates")
      where path.hasSuffix(suffix) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
        found.append((modified ?? .distantPast, path))
      }
    }
    return found.max { ($0.modified, $0.path) < ($1.modified, $1.path) }?.path
  }

  func xcode() throws {
    let location = derivedData ?? defaultDerivedDataRoot
    guard let configs = synthesizedConfigs() else {
      throw fail(
        "no configs the plugin synthesized for \(target) under \(location) — build \(target) once, or pass --derived-data")
    }
    let dd = String(configs[..<configs.range(of: "/Build/Intermediates.noindex/")!.lowerBound])
    let workspace = workspacePath(derivedData: dd)
    let projectDirectory =
      project
      ?? ((workspace ?? FileManager.default.currentDirectoryPath + "/.") as NSString).deletingLastPathComponent

    // The plugin keeps the author's file name, and `.Sourcery.Mocks.yml` is a dotfile.
    let configFiles = ((try? FileManager.default.contentsOfDirectory(atPath: configs)) ?? [])
      .map { "\(configs)/\($0)" }
      .filter { isRegularFile($0) }
      .sorted()
    guard !configFiles.isEmpty else { throw fail("\(configs) holds no config") }

    // The engine: the one --engine names; beside the shipped templates a config names by absolute
    // path — an artifact bundle holds both, and a package checkout's SourcePackages holds the bundle
    // under artifacts/; beside this binary, when it runs from an artifact bundle; else under this
    // derived data's own SourcePackages.
    let template = firstTemplatePath(in: configFiles)
    var templatesDirectory = template.map { ($0 as NSString).deletingLastPathComponent }
    var engine = self.engine.flatMap { $0.isEmpty ? nil : $0 }
    if engine == nil, let templatesDirectory {
      let root = (templatesDirectory as NSString).deletingLastPathComponent
      if FileManager.default.fileExists(atPath: "\(root)/info.json") {
        engine = "\(root)/sourcery/bin/sourcery"
      } else {
        let packages = root.range(of: "/checkouts/", options: .backwards).map { String(root[..<$0.lowerBound]) } ?? root
        engine = regularFiles(under: "\(packages)/artifacts").first { $0.hasSuffix("/sourcery/bin/sourcery") }
      }
    }
    if engine == nil {
      engine = engineBesideThisBinary()
    }
    if engine == nil {
      engine = regularFiles(under: "\(dd)/SourcePackages/artifacts").first { $0.hasSuffix("/sourcery/bin/sourcery") }
    }
    guard let engine, FileManager.default.isExecutableFile(atPath: engine) else {
      throw fail("no Sourcery engine found for \(dd) — pass --engine")
    }
    if templatesDirectory == nil {
      let candidate = URL(fileURLWithPath: engine).deletingLastPathComponent()
        .appendingPathComponent("../../templates").standardizedFileURL.path
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
        templatesDirectory = candidate
      }
    }

    let work = "\(dd)/Build/Intermediates.noindex/PrintMocks"
    let manager = FileManager.default
    try? manager.removeItem(atPath: "\(work)/\(target)")
    for directory in ["\(work)/\(target)/.configs", "\(work)/.cache", "\(work)/.build"] {
      try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }
    let gitRoot = (try? stdoutOf(["git", "-C", projectDirectory, "rev-parse", "--show-toplevel"]))
      .flatMap { $0.status == 0 ? $0.stdout : nil } ?? ""

    for config in configFiles {
      let name = (config as NSString).lastPathComponent
      // The output directory's name, as the plugin's directoryName(for:) derives it.
      var stem = Substring(name)
      while stem.hasPrefix(".") { stem = stem.dropFirst() }
      if let dot = stem.lastIndex(of: ".") { stem = stem[..<dot] }
      let out = "\(work)/\(target)/\(stem)"
      try manager.createDirectory(atPath: out, withIntermediateDirectories: true)
      let copy = "\(work)/\(target)/.configs/\(name)"
      try rewriteOutput(config: config, to: out, writing: copy)

      // The four variables the plugin's Xcode half exports to the engine.
      var environment = ProcessInfo.processInfo.environment
      environment["SOURCERY_PROJECT"] = projectDirectory
      environment["GIT_ROOT"] = gitRoot
      environment["SOURCERY_TEMPLATES"] = templatesDirectory ?? ""
      environment["SOURCERY_OUTPUT_DIR"] = out
      let log = "\(copy).log"
      let status = try runLogged(
        executable: engine,
        arguments: ["--config", copy, "--cacheBasePath", "\(work)/.cache", "--buildPath", "\(work)/.build", "--quiet"],
        environment: environment, log: log)
      if status != 0 {
        writeErr((try? Data(contentsOf: URL(fileURLWithPath: log))) ?? Data())
        throw fail("the engine failed on \(name) for \(target)")
      }
    }

    let files = regularFiles(under: "\(work)/\(target)").filter { path in
      path.hasSuffix(".generated.swift") && !path.contains("/.configs/")
    }
    try printGenerated(files.sorted())
  }

  /// The workspace a derived data directory was built for, from its info.plist.
  func workspacePath(derivedData: String) -> String? {
    guard let data = FileManager.default.contents(atPath: "\(derivedData)/info.plist"),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return nil }
    return plist["WorkspacePath"] as? String
  }

  /// The first `"…/templates/<name>.swifttemplate"` path the configs name, in file order.
  func firstTemplatePath(in configFiles: [String]) -> String? {
    let pattern = try! NSRegularExpression(pattern: #""([^"]*/templates/[^"/]*\.swifttemplate)""#)
    for file in configFiles {
      guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      if let match = pattern.firstMatch(in: text, range: range), let path = Range(match.range(at: 1), in: text) {
        return String(text[path])
      }
    }
    return nil
  }

  /// `<bundle>/sourcery/bin/sourcery`, when this binary is `<bundle>/mock-templates/bin/mock-templates`
  /// of an artifact bundle.
  func engineBesideThisBinary() -> String? {
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
    let bin = executable.deletingLastPathComponent()
    let product = bin.deletingLastPathComponent()
    guard bin.lastPathComponent == "bin", product.lastPathComponent == "mock-templates" else { return nil }
    let bundle = product.deletingLastPathComponent()
    guard FileManager.default.fileExists(atPath: bundle.appendingPathComponent("info.json").path) else { return nil }
    let candidate = bundle.appendingPathComponent("sourcery/bin/sourcery").path
    return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
  }

  /// The config with its `output:` line pointed at `out`, every other line copied.
  func rewriteOutput(config: String, to out: String, writing copy: String) throws {
    let text = try String(contentsOfFile: config, encoding: .utf8)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if text.hasSuffix("\n") { lines.removeLast() }
    let rewritten = lines.map { $0.hasPrefix("output:") ? "output: \"\(out)\"" : $0 }
    try (rewritten.map { $0 + "\n" }.joined()).write(toFile: copy, atomically: true, encoding: .utf8)
  }

  // ── messages ──────────────────────────────────────────────────────

  func fail(_ message: String) -> ExitCode {
    writeErr("mock-templates: \(message)\n")
    return .failure
  }

  func note(_ message: String) {
    writeErr("mock-templates: \(message)\n")
  }
}

// ── processes and files ─────────────────────────────────────────────

private var hostArchitecture: String {
  #if arch(arm64)
    return "arm64"
  #else
    return "x86_64"
  #endif
}

private func writeOut(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }
private func writeOut(_ data: Data) { FileHandle.standardOutput.write(data) }
private func writeErr(_ text: String) { FileHandle.standardError.write(Data(text.utf8)) }
private func writeErr(_ data: Data) { FileHandle.standardError.write(data) }

private func launch(_ arguments: [String], stdout: Any, stderr: Any) throws -> Process {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  process.standardInput = FileHandle.nullDevice
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  return process
}

/// Runs a command found on PATH with its stdout discarded, and returns its stderr.
private func stderrOf(_ arguments: [String]) throws -> (status: Int32, stderr: String) {
  let pipe = Pipe()
  let process = try launch(arguments, stdout: FileHandle.nullDevice, stderr: pipe)
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// Runs a command found on PATH with its stderr discarded, and returns its stdout, trimmed.
private func stdoutOf(_ arguments: [String]) throws -> (status: Int32, stdout: String) {
  let pipe = Pipe()
  let process = try launch(arguments, stdout: pipe, stderr: FileHandle.nullDevice)
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  return (process.terminationStatus, text)
}

/// Runs an executable with stdout and stderr written to `log`.
private func runLogged(executable: String, arguments: [String], environment: [String: String], log: String) throws
  -> Int32
{
  FileManager.default.createFile(atPath: log, contents: nil)
  let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
  defer { try? handle.close() }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.environment = environment
  process.standardInput = FileHandle.nullDevice
  process.standardOutput = handle
  process.standardError = handle
  try process.run()
  process.waitUntilExit()
  return process.terminationStatus
}

/// The path with every symbolic link resolved, `/private` kept — what `pwd -P` prints.
private func physicalPath(_ path: String) -> String? {
  guard let resolved = realpath(path, nil) else { return nil }
  defer { free(resolved) }
  return String(cString: resolved)
}

private func isRegularFile(_ path: String) -> Bool {
  (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular
}

/// Every regular file under `root`, each as `root` joined with its relative path.
private func regularFiles(under root: String) -> [String] {
  guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
  var files: [String] = []
  while let relative = enumerator.nextObject() as? String {
    if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular {
      files.append("\(root)/\(relative)")
    }
  }
  return files
}

/// Every directory under `root`, each as `root` joined with its relative path.
private func directories(under root: String) -> [String] {
  guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
  var found: [String] = []
  while let relative = enumerator.nextObject() as? String {
    if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
      found.append("\(root)/\(relative)")
    }
  }
  return found
}
