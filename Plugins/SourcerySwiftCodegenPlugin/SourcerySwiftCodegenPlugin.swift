import Foundation
import PackagePlugin

// The plugin is one file on purpose: a build-tool plugin cannot depend on a
// library target, so there is no Yams, no shared code with Sources/mock-templates
// and no unit-test target that can import any of this. See
// specs/001-plugin-source-discovery/spec.md §1.5, and
// Tests/Checks/run-plugin-checks.sh for the black-box lane that stands in for
// the tests this file cannot have.

/// This package's manifest name, used to find it in a consumer's graph (§4.5).
/// The manifest name lives in this repository, so it survives a consumer
/// vendoring the package under another directory name — which is what changes
/// the identity below.
let pluginPackageName = "SourcerySwiftCodegen"

/// The identity a consumer gets from the canonical repository URL. Checked
/// alongside the manifest name so a fork that renamed one of the two is still
/// recognised.
let pluginPackageIdentity = "swift-sourcery-templates"

/// The list item an author writes where the derived source closure should go.
/// Deliberately not an env var (§9, D7): nothing exports `SOURCERY_SOURCES`, so a
/// substitution that failed to run leaves Sourcery reporting an unexpanded path
/// instead of silently scanning less than intended.
let sourcesPlaceholder = "${SOURCERY_SOURCES}"

protocol CodegenPluginContext {
  var rootDirectory: PackagePlugin.Path { get }
  var pluginWorkDirectory: PackagePlugin.Path { get }
  func tool(named name: String) throws -> PackagePlugin.PluginContext.Tool
  var environmentVars: [String: String] { get }

  /// The `templates/` directory of the package shipping this plugin, when the
  /// graph can be walked for it (§4.5). `nil` in Xcode projects, where
  /// `XcodePluginContext` exposes no package graph — a bare template name then
  /// stays unresolved and warns.
  var shippedTemplatesDirectory: PackagePlugin.Path? { get }
}

protocol CodegenPluginTarget {
  var name: String { get }
  func sourceryConfigFileLocations(rootDirectory: Path) -> Set<Path>

  /// The directories `${SOURCERY_SOURCES}` expands to: the target's own sources
  /// plus the recursive closure of its dependencies, first-party and external
  /// alike (§3.1). Deduplicated, descendants of another entry dropped, sorted.
  var derivedSourceRoots: [Path] { get }

  /// The module `args.testable` names when exactly one module can be meant (§4.6).
  var testableDefault: TestableDefault { get }
}

/// What the plugin can say about the module under test (§4.6, D11). Derived from
/// the *direct* target dependencies, never the closure: the module a test target
/// tests is the one it depends on, not one it reaches through that.
enum TestableDefault {
  /// Not a test target, or a context with no graph to derive from.
  case notApplicable
  /// Exactly one candidate — not a guess, the answer.
  case unambiguous(String)
  /// Zero, or more than one. The plugin inserts nothing and names what it found.
  case ambiguous([String])
}

private func gitRootDirectory(_ path: Path) -> String {
  let task = Process()
  task.launchPath = "/usr/bin/env"
  task.currentDirectoryURL = URL(filePath: path.string)
  task.arguments = ["git", "rev-parse", "--show-toplevel"]

  let outputPipe = Pipe()
  let errorPipe = Pipe()
  task.standardOutput = outputPipe
  task.standardError = errorPipe
  let outHandle = outputPipe.fileHandleForReading
  let errorHandle = errorPipe.fileHandleForReading

  task.launch()

  let outputData = outHandle.readDataToEndOfFile()
  let errorData = errorHandle.readDataToEndOfFile()
  outHandle.closeFile()
  errorHandle.closeFile()

  task.waitUntilExit()

  let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

  guard task.terminationStatus == 0 else {
    Diagnostics.warning("Error running git command: \(task.terminationStatus): \(error)")
    return ""
  }

  return output
}

private func locateSourceryExecutable(_ context: CodegenPluginContext) throws -> Path {
  let sourcery = try context.tool(named: "sourcery").path
  if sourcery.fileExists && !sourcery.isDirectory && sourcery.isExecutable {
    return sourcery
  }

  // If artifactsbundle is zipped incorrectly, the execuitable ends up one nesting level deeper than needed.
  let sourceryNestedDirectory = sourcery.appending("bin", "sourcery")
  if sourceryNestedDirectory.fileExists && !sourceryNestedDirectory.isDirectory && sourceryNestedDirectory.isExecutable {
    return sourceryNestedDirectory
  }

  throw SourcerySwiftCodegenPluginError.sourceryNotFound(path: sourcery.string)
}

enum SourcerySwiftCodegenPluginError: Error, LocalizedError {
  case sourceryNotFound(path: String)
  case configUnreadable(path: String, underlying: String)
  case configurationRejected(target: String, reasons: [String])

  var errorDescription: String? {
    switch self {
    case .sourceryNotFound(let path):
      return "Could not locate Sourcery executable in the tool path '\(path)'"
    case .configUnreadable(let path, let underlying):
      return "Could not read the Sourcery config at '\(path)': \(underlying)"
    case .configurationRejected(let target, let reasons):
      return "Target \"\(target)\": the Sourcery configuration was rejected:\n - "
        + reasons.joined(separator: "\n - ")
    }
  }
}

// MARK: - Reading a config by line, not by parser

// D1: a hand-written YAML parser deciding what a consumer's config means is a
// much larger liability than a line-level substitution, so the synthesizer
// recognises exactly the shapes it rewrites — a mapping key at a known
// indentation, and a whole list item — and copies every other byte through.

/// A `key:` mapping entry: its indentation, its name and whatever follows the colon.
struct MappingKey {
  let indent: Int
  let name: String
  let value: String
}

/// A `- value` sequence entry: its indentation and the value.
struct ListItem {
  let indent: Int
  let value: String
}

enum YamlLine {
  /// The number of leading spaces, or `nil` for a blank line or one indented with
  /// a tab (which is not YAML indentation, so such a line is never read as nested).
  static func indent(of line: String) -> Int? {
    var count = 0
    for character in line {
      if character == " " {
        count += 1
      } else if character == "\t" || character == "\r" {
        return nil
      } else {
        return count
      }
    }
    return nil
  }

  static func isBlankOrComment(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.hasPrefix("#")
  }

  /// The mapping key this line declares, if it declares one.
  static func mappingKey(of line: String) -> MappingKey? {
    guard let indent = indent(of: line) else { return nil }
    var rest = Substring(line).dropFirst(indent)
    guard let first = rest.first, first.isLetter || first == "_" else { return nil }
    var name = ""
    while let character = rest.first, character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." {
      name.append(character)
      rest = rest.dropFirst()
    }
    while rest.first == " " { rest = rest.dropFirst() }
    guard rest.first == ":" else { return nil }
    rest = rest.dropFirst()
    return MappingKey(indent: indent, name: name, value: String(rest).trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// The sequence entry this line declares, if it declares one.
  static func listItem(of line: String) -> ListItem? {
    guard let indent = indent(of: line) else { return nil }
    var rest = Substring(line).dropFirst(indent)
    guard rest.first == "-" else { return nil }
    rest = rest.dropFirst()
    guard rest.isEmpty || rest.first == " " else { return nil }
    return ListItem(indent: indent, value: String(rest).trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// A scalar with its surrounding quotes removed, and a trailing `# comment`
  /// dropped when the value was not quoted.
  static func scalar(_ raw: String) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
      let inner = String(value.dropFirst().dropLast())
      return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"") : inner
    }
    // An unquoted scalar ends at a ` #` comment.
    if let range = value.range(of: " #") {
      return String(value[value.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return value
  }

  /// A path emitted by the plugin, as a double-quoted YAML scalar. Paths contain
  /// spaces routinely — a DerivedData path always can — so quoting is not optional.
  static func quoted(_ path: String) -> String {
    let escaped = path
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}

/// The output subdirectory a config owns, from its file name: `.Sourcery.Mocks.yml`
/// becomes `Sourcery.Mocks`. Stable across builds, and legible in a build log.
func directoryName(for configFileName: String) -> String {
  var name = configFileName
  while name.hasPrefix(".") { name.removeFirst() }
  if let dot = name.range(of: ".", options: .backwards) {
    name = String(name[name.startIndex..<dot.lowerBound])
  }
  let allowed = name.map { character -> Character in
    character.isLetter || character.isNumber || character == "." || character == "-" || character == "_" ? character : "_"
  }
  let sanitized = String(allowed)
  return sanitized.isEmpty ? "Sourcery" : sanitized
}

/// `.`/`..` removed, `~` expanded and any trailing slash dropped, so two spellings
/// of one directory compare equal.
func normalizedPath(_ path: String) -> String {
  var standardized = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
  while standardized.count > 1 && standardized.hasSuffix("/") {
    standardized.removeLast()
  }
  return standardized
}

/// Deduplicated, with any path contained in another dropped, then sorted (§3.3).
/// `recursiveTargetDependencies` promises a dependency order, not a stable one
/// across resolutions, and the synthesized config has to be byte-identical
/// between builds or Sourcery's cache is invalidated every time (§1.5).
func normalizedSourceRoots(_ paths: [Path]) -> [Path] {
  var unique: [String] = []
  var seen = Set<String>()
  for path in paths {
    let normalized = normalizedPath(path.string)
    if seen.insert(normalized).inserted {
      unique.append(normalized)
    }
  }
  let kept = unique.filter { candidate in
    !unique.contains { other in other != candidate && candidate.hasPrefix(other + "/") }
  }
  return kept.sorted().map { Path($0) }
}

// MARK: - Config synthesis (§4)

/// Copies an author's Sourcery config into the plugin's work directory, expanding
/// what it declares and appending what it omits (§4.2):
///
///   1. `- ${SOURCERY_SOURCES}` becomes one quoted directory per module in the closure.
///   2. A bare `templates:` entry becomes the absolute path of the template it names.
///   3. `sources:` and `output:` are appended when the document declares neither
///      them nor an equivalent, and `args.testable` is inserted when the module
///      under test is unambiguous.
///   4. An `output:` the config declares is verified against the directory the
///      build actually collects from — a mismatch is an error, not a rewrite.
///   5. Every other byte is copied through, comments and all.
///
/// A config with no placeholder, no bare name, both keys present and an
/// `args.testable` of its own comes out byte-identical.
struct SourceryConfigSynthesizer {
  let configPath: Path
  let sourceRoots: [Path]
  let shippedTemplatesDirectory: Path?
  let generatedFilesDir: Path
  let testableDefault: TestableDefault
  let environmentVars: [String: String]

  struct Result {
    var text = ""
    var remarks: [String] = []
    var warnings: [String] = []
    var errors: [String] = []
    /// The `<name>.generated.swift` files this config will write, one per
    /// `templates:` entry (§1.4/F). Used for the collision check of §4.7.
    var generatedFileStems: [String] = []
  }

  /// What a first pass can see about the document, so the second pass can insert
  /// into it without re-deriving state mid-rewrite.
  private struct Shape {
    var topLevelKeys: Set<String> = []
    var argsLine: Int?
    var argsIsFlowStyle = false
    var argsChildIndent: Int?
    var argsHasTestable = false
  }

  private func scan(_ lines: [String]) -> Shape {
    var shape = Shape()
    var currentTopKey: String?
    for (index, line) in lines.enumerated() {
      if YamlLine.isBlankOrComment(line) { continue }
      if let key = YamlLine.mappingKey(of: line), key.indent == 0 {
        // Column 0 only. This is the shape of every config this repo ships or
        // documents, and a commented-out `# package:` block cannot match it.
        shape.topLevelKeys.insert(key.name)
        currentTopKey = key.name
        if key.name == "args" {
          shape.argsLine = index
          shape.argsIsFlowStyle = key.value.hasPrefix("{")
        }
        continue
      }
      guard let indent = YamlLine.indent(of: line), indent > 0 else {
        currentTopKey = nil
        continue
      }
      if currentTopKey == "args" {
        if shape.argsChildIndent == nil { shape.argsChildIndent = indent }
        if let key = YamlLine.mappingKey(of: line), key.name == "testable", key.indent == shape.argsChildIndent {
          shape.argsHasTestable = true
        }
      }
    }
    return shape
  }

  func synthesize(_ original: String) -> Result {
    var result = Result()
    let lines = original.components(separatedBy: "\n")
    let shape = scan(lines)
    var rewritten: [String] = []
    rewritten.reserveCapacity(lines.count + sourceRoots.count + 8)

    var currentTopKey: String?
    var expandedPlaceholder = false
    var suppliedDefaults: [String] = []
    // Values already reported by the template rules, so the relative-path audit
    // does not report them a second time.
    var reportedValues = Set<String>()

    for (index, line) in lines.enumerated() {
      if !YamlLine.isBlankOrComment(line) {
        if let key = YamlLine.mappingKey(of: line), key.indent == 0 {
          currentTopKey = key.name
        } else if let indent = YamlLine.indent(of: line), indent == 0 {
          currentTopKey = nil
        }
      }

      // 1. The source closure.
      if currentTopKey == "sources",
         let item = YamlLine.listItem(of: line),
         YamlLine.scalar(item.value) == sourcesPlaceholder {
        let padding = String(repeating: " ", count: item.indent)
        for root in sourceRoots {
          rewritten.append("\(padding)- \(YamlLine.quoted(root.string))")
        }
        expandedPlaceholder = true
        continue
      }
      // The placeholder is recognised only under `sources:` (§4.1). Anywhere else
      // it would reach Sourcery unexpanded, so say so rather than let it fail
      // with a path nobody wrote.
      if currentTopKey != "sources",
         let item = YamlLine.listItem(of: line),
         YamlLine.scalar(item.value) == sourcesPlaceholder {
        result.warnings.append(
          "\(configPath.lastComponent):\(index + 1): \(sourcesPlaceholder) is only expanded under `sources:`, and this one is under `\(currentTopKey ?? "no key")`. Left as written.")
        rewritten.append(line)
        continue
      }

      // 2. Bare template names.
      if currentTopKey == "templates", let item = YamlLine.listItem(of: line), !item.value.isEmpty {
        let named = YamlLine.scalar(item.value)
        let resolution = resolveTemplate(named)
        if let stem = resolution.stem {
          result.generatedFileStems.append(stem)
        }
        if let remark = resolution.remark { result.remarks.append(remark) }
        if let warning = resolution.warning {
          result.warnings.append(warning)
          reportedValues.insert(named)
        }
        if let resolved = resolution.path {
          rewritten.append("\(String(repeating: " ", count: item.indent))- \(YamlLine.quoted(resolved.string))")
          continue
        }
        rewritten.append(line)
        continue
      }

      rewritten.append(line)

      // 3. `args.testable`, the one nested insert (§4.6).
      if let argsLine = shape.argsLine, index == argsLine, case let .unambiguous(module) = testableDefault {
        if shape.argsHasTestable {
          result.remarks.append("\(configPath.lastComponent): `args.testable` is already set — left as written.")
        } else if shape.argsIsFlowStyle {
          result.remarks.append("\(configPath.lastComponent): `args:` is written in flow style, so `testable: [\(module)]` was not inserted. Add it by hand if the mocks need it.")
        } else if let childIndent = shape.argsChildIndent {
          rewritten.append("\(String(repeating: " ", count: childIndent))testable: [\(module)]")
          suppliedDefaults.append("args.testable: [\(module)]")
        } else {
          result.remarks.append("\(configPath.lastComponent): `args:` has no entries to match the indentation of, so `testable: [\(module)]` was not inserted.")
        }
      }
    }

    // 3 (continued). The keys with a single right answer, appended (D10).
    var appended: [String] = []
    let declaresInputs = !shape.topLevelKeys.isDisjoint(with: ["sources", "project", "package"])
    if !declaresInputs {
      appended.append("sources:")
      for root in sourceRoots {
        appended.append("  - \(YamlLine.quoted(root.string))")
      }
      suppliedDefaults.append("sources: the derived closure (\(sourceRoots.count) director\(sourceRoots.count == 1 ? "y" : "ies"))")
    }
    if !shape.topLevelKeys.contains("output") {
      appended.append("output: \(YamlLine.quoted(generatedFilesDir.string))")
      suppliedDefaults.append("output: \(generatedFilesDir.string)")
    }
    if !shape.argsHasTestable, case .ambiguous(let candidates) = testableDefault {
      result.remarks.append(
        candidates.isEmpty
          ? "\(configPath.lastComponent): no root-package module is a direct dependency of the test target, so `args.testable` was not inserted."
          : "\(configPath.lastComponent): the test target directly depends on \(candidates.count) root-package modules (\(candidates.joined(separator: ", "))), so `args.testable` was not inserted — name the one the mocks belong to.")
    }

    if !appended.isEmpty {
      // Splice the block on with exactly one trailing newline, whatever the
      // original ended with.
      while let last = rewritten.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        rewritten.removeLast()
      }
      rewritten.append(contentsOf: appended)
      rewritten.append("")
    }

    if !suppliedDefaults.isEmpty {
      result.remarks.append("\(configPath.lastComponent): the plugin supplied \(suppliedDefaults.joined(separator: "; ")).")
    }
    if expandedPlaceholder {
      result.remarks.append("\(configPath.lastComponent): \(sourcesPlaceholder) expanded to \(sourceRoots.count) director\(sourceRoots.count == 1 ? "y" : "ies").")
    }

    result.text = rewritten.joined(separator: "\n")

    // 4. Verify an `output:` the config declares, and 5's contract: absolute paths.
    verifyOutput(rewritten, into: &result)
    auditRelativePaths(rewritten, reportedValues: reportedValues, into: &result)

    return result
  }

  // MARK: Template resolution (§4.5)

  private struct TemplateResolution {
    var path: Path?
    var stem: String?
    var remark: String?
    var warning: String?
  }

  private func resolveTemplate(_ named: String) -> TemplateResolution {
    // 1. A path. Left alone — but its basename still tells us what Sourcery will
    //    write, which is what the collision check of §4.7 needs.
    if named.contains("/") || named.hasPrefix("$") {
      let last = String(named.split(separator: "/").last ?? "")
      return TemplateResolution(path: nil, stem: last.contains("$") ? nil : Path(last).stem)
    }

    // 2. A file beside the author's config — today's meaning of a relative entry.
    //    Ordered before the shipped templates so a consumer with its own
    //    `Mocks.swifttemplate` keeps getting its own file.
    let beside = configPath.removingLastComponent().appending(named)
    if beside.fileExists && !beside.isDirectory {
      return TemplateResolution(
        path: beside,
        stem: beside.stem,
        remark: "\(configPath.lastComponent): template '\(named)' resolved to the file beside the config, \(beside.string).")
    }

    // 3. A template shipped by this package.
    if let templatesDirectory = shippedTemplatesDirectory {
      for candidate in [templatesDirectory.appending(named + ".swifttemplate"), templatesDirectory.appending(named)] {
        // `_header.swifttemplate` is an include, not something to run.
        guard candidate.fileExists, !candidate.isDirectory, !candidate.lastComponent.hasPrefix("_") else { continue }
        return TemplateResolution(
          path: candidate,
          stem: candidate.stem,
          remark: "\(configPath.lastComponent): template '\(named)' resolved to the shipped \(candidate.lastComponent).")
      }
    }

    // 4. Neither. Sourcery then fails on it, which is the right outcome for a typo.
    let shipped = shippedTemplatesDirectory.map { listShippedTemplates($0) } ?? []
    let available = shipped.isEmpty
      ? "no shipped templates are reachable from here — an Xcode project has no package graph to find them in, so name the template by path"
      : "the shipped templates are \(shipped.joined(separator: ", "))"
    return TemplateResolution(
      path: nil,
      stem: Path(named).stem,
      warning: "\(configPath.lastComponent): template '\(named)' is neither a file beside the config nor a shipped template — \(available).")
  }

  private func listShippedTemplates(_ directory: Path) -> [String] {
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.string)) ?? []
    return contents
      .filter { $0.hasSuffix(".swifttemplate") && !$0.hasPrefix("_") }
      .map { Path($0).stem }
      .sorted()
  }

  // MARK: `output:` verification (§4.6, D12)

  private func verifyOutput(_ lines: [String], into result: inout Result) {
    var currentTopKey: String?
    var outputIndent: Int?
    var declaredValue: String?
    var sawObjectForm = false

    for line in lines {
      if YamlLine.isBlankOrComment(line) { continue }
      if let key = YamlLine.mappingKey(of: line), key.indent == 0 {
        currentTopKey = key.name
        if key.name == "output" {
          if key.value.isEmpty {
            sawObjectForm = true
            outputIndent = nil
          } else {
            declaredValue = YamlLine.scalar(key.value)
          }
        }
        continue
      }
      guard currentTopKey == "output", sawObjectForm else { continue }
      guard let key = YamlLine.mappingKey(of: line), key.indent > 0 else { continue }
      if outputIndent == nil { outputIndent = key.indent }
      if key.name == "path", key.indent == outputIndent {
        declaredValue = YamlLine.scalar(key.value)
      }
    }

    guard let declared = declaredValue else {
      if sawObjectForm {
        result.warnings.append("\(configPath.lastComponent): `output:` is an object with no `path:` the line rules can read, so the output directory was not verified. It must be \(generatedFilesDir.string).")
      }
      return
    }

    let expanded = expandEnvironment(declared)
    if expanded.contains("$") {
      result.warnings.append("\(configPath.lastComponent): `output:` still contains an unexpanded variable after substitution ('\(expanded)'), so the output directory was not verified. It must be \(generatedFilesDir.string).")
      return
    }
    // A relative value means "relative to the config file's directory" — the
    // author's directory, which is what it means today (§1.4/A).
    let absolute = expanded.hasPrefix("/")
      ? expanded
      : configPath.removingLastComponent().appending(expanded).string
    let required = normalizedPath(generatedFilesDir.string)
    let resolved = normalizedPath(absolute)
    guard resolved != required,
          (resolved as NSString).resolvingSymlinksInPath != (required as NSString).resolvingSymlinksInPath else {
      return
    }
    // Outputs are collected only from the command's `outputFilesDirectory`, so a
    // file written anywhere else is written and then ignored: the target compiles
    // without it and the failure surfaces as a missing type, far from its cause.
    result.errors.append(
      "\(configPath.lastComponent): `output:` resolves to '\(resolved)', but the build collects generated files only from '\(required)'. Remove the key and let the plugin supply it, or set it to ${SOURCERY_OUTPUT_DIR}.")
  }

  private func expandEnvironment(_ value: String) -> String {
    var expanded = value
    for (name, replacement) in environmentVars {
      expanded = expanded.replacingOccurrences(of: "${\(name)}", with: replacement)
    }
    return expanded
  }

  // MARK: The absolute-path contract (§4.3)

  /// The synthesized copy lives in `pluginWorkDirectory`, and a relative path in a
  /// config resolves against the config file's own directory (§1.4/A) — so a
  /// relative path that works today would silently resolve somewhere else. The
  /// plugin does not rewrite them (that needs the parser it does not have); it
  /// names them. A warning, not an error: the heuristic is not good enough to
  /// block a build on.
  private func auditRelativePaths(_ lines: [String], reportedValues: Set<String>, into result: inout Result) {
    let pathKeys: Set<String> = ["sources", "templates", "output"]
    var currentTopKey: String?
    for (index, line) in lines.enumerated() {
      if YamlLine.isBlankOrComment(line) { continue }
      var value: String?
      if let key = YamlLine.mappingKey(of: line) {
        if key.indent == 0 {
          currentTopKey = key.name
          value = key.value.isEmpty ? nil : YamlLine.scalar(key.value)
        } else if currentTopKey == "output" && key.name == "path" {
          value = YamlLine.scalar(key.value)
        }
      } else if let item = YamlLine.listItem(of: line), !item.value.isEmpty {
        value = YamlLine.scalar(item.value)
      } else if let indent = YamlLine.indent(of: line), indent == 0 {
        currentTopKey = nil
      }

      guard let currentTopKey, pathKeys.contains(currentTopKey) else { continue }
      guard let value, !value.isEmpty, !reportedValues.contains(value) else { continue }
      guard let first = value.unicodeScalars.first else { continue }
      guard CharacterSet.alphanumerics.contains(first) || first == "." || first == "_" else { continue }
      result.warnings.append(
        "\(configPath.lastComponent):\(index + 1): '\(value)' under `\(currentTopKey):` looks like a relative path. The plugin runs a copy of this config from its own work directory, where a relative path means something else — write it absolutely, or name a shipped template by name.")
    }
  }
}

// MARK: - The plugin

@main
struct SourcerySwiftCodegenPlugin {
  func _createBuildCommands(context: CodegenPluginContext, target: CodegenPluginTarget) throws -> [Command] {

    let sourcery = try locateSourceryExecutable(context)
    Diagnostics.remark("Sourcery executable: '\(sourcery)'")

    // A derived location that is not there is skipped, not reported. In an Xcode
    // project a target that depends on a sibling target carries the linked
    // framework in `inputFiles` — `<project>/build/Debug/Core.framework` — and
    // the location derived from it, `<project>/build`, exists only if that
    // project happened to be built in place. Reporting the missing directory as
    // an error failed the build, at plan time, for every Xcode project with a
    // dependency between two of its own targets (001 follow-up §1.4, F1). A
    // location that *is* there and will not open keeps its error below: that is a
    // real problem with a real cause, and silencing it would hide it.
    let sourceryConfigFileLocations = target
      .sourceryConfigFileLocations(rootDirectory: context.rootDirectory)
      .filter { $0.isDirectory }
      .sorted { $0.string < $1.string }
    let sourceryConfigFilePaths = sourceryConfigFileLocations.flatMap { location in
      do {
        let files = try FileManager.default.contentsOfDirectory(atPath: location.string)
        return files.filter { $0.matches(rgSourcery) }.map { location.appending($0) }
      } catch let e {
        Diagnostics.error("\(e)")
        return []
      }
    }.sorted { $0.string < $1.string }
    Diagnostics.remark("Target \"\(target.name)\"\n - looking for Sourcery configs in: \(sourceryConfigFileLocations)\n - found configs: \(sourceryConfigFilePaths.map { $0.lastComponent })")

    // Write caches "SourceryCaches" subdirectory of the plugin work directory
    // (which is unique for each plugin and target).
    let perTargetCachesFilesDir = context.pluginWorkDirectory.appending(".sourceryCaches")
    try FileManager.default.createDirectory(atPath: perTargetCachesFilesDir.string, withIntermediateDirectories: true)

    // Per-target build directory
    // (which is unique for each plugin and target).
    let perTargetBuildDir = context.pluginWorkDirectory.appending(".sourceryBuild")
    try FileManager.default.createDirectory(atPath: perTargetBuildDir.string, withIntermediateDirectories: true)

    // Generated files go under ".generatedFiles", one subdirectory per config.
    //
    // Per config, not per target, and that is not a tidiness choice: a prebuild
    // command's outputs are collected by scanning the whole directory it declared,
    // so two commands of one target declaring one directory makes SwiftPM attribute
    // every file in it to both of them and refuse the build outright —
    // "couldn't build <file>.o because of multiple producers". A target carrying
    // several configs is the shape §4.7 encourages, so each config owns a
    // directory nothing else writes to.
    let generatedFilesRoot = context.pluginWorkDirectory.appending(".generatedFiles")
    try FileManager.default.createDirectory(atPath: generatedFilesRoot.string, withIntermediateDirectories: true)

    // The configs the plugin actually runs: a copy of each authored config with
    // the closure spliced in and the omitted keys supplied (§4.4).
    let synthesizedConfigsDir = context.pluginWorkDirectory.appending(".sourceryConfigs")
    try FileManager.default.createDirectory(atPath: synthesizedConfigsDir.string, withIntermediateDirectories: true)

    var sharedEnvironmentVars = context.environmentVars
    if let templatesDirectory = context.shippedTemplatesDirectory {
      sharedEnvironmentVars["SOURCERY_TEMPLATES"] = templatesDirectory.string
    }

    let sourceRoots = target.derivedSourceRoots
    Diagnostics.remark("Target \"\(target.name)\": \(sourcesPlaceholder) resolves to \(sourceRoots.count) source director\(sourceRoots.count == 1 ? "y" : "ies").")

    struct RunnableConfig {
      let original: Path
      let synthesized: Path
      let outputDir: Path
      let environmentVars: [String: String]
    }

    var errors: [String] = []
    // §4.7: the configs of one target all put their output on that target's compile
    // path, so two of them naming the same template produce two files declaring the
    // same types. Caught here, where the config can be named, rather than as a
    // redeclaration error in generated code.
    var stemOwners: [String: Path] = [:]
    var runnableConfigs: [RunnableConfig] = []

    // Two configs of one target must not land on one synthesized file or one
    // output directory. Distinct names normally guarantee both, but the discovery
    // regex accepts any `*.sourcery*.yml` and `directoryName(for:)` strips leading
    // dots, so `.Sourcery.A.yml` and `..Sourcery.A.yml` would collide — and a
    // collision here is the "multiple producers" build failure again, with nothing
    // naming its cause.
    var usedFileNames = Set<String>()
    var usedDirectoryNames = Set<String>()
    func claim(_ preferred: String, from taken: inout Set<String>, extension suffix: String) -> String {
      if taken.insert(preferred).inserted { return preferred }
      var attempt = 2
      while true {
        let candidate = suffix.isEmpty ? "\(preferred)-\(attempt)" : "\(Path(preferred).stem)-\(attempt).\(suffix)"
        if taken.insert(candidate).inserted { return candidate }
        attempt += 1
      }
    }

    for configFilePath in sourceryConfigFilePaths {
      let original: String
      do {
        original = try String(contentsOfFile: configFilePath.string, encoding: .utf8)
      } catch let error {
        throw SourcerySwiftCodegenPluginError.configUnreadable(path: configFilePath.string, underlying: "\(error)")
      }

      // Keep the author's basename so the command's displayName, and any Sourcery
      // diagnostic naming the config, still name something they recognise.
      let fileName = claim(
        configFilePath.lastComponent,
        from: &usedFileNames,
        extension: configFilePath.extension ?? "yml")
      let outputDir = generatedFilesRoot.appending(
        claim(directoryName(for: fileName), from: &usedDirectoryNames, extension: ""))
      try FileManager.default.createDirectory(atPath: outputDir.string, withIntermediateDirectories: true)

      var environmentVars = sharedEnvironmentVars
      environmentVars["SOURCERY_OUTPUT_DIR"] = outputDir.string

      let synthesizer = SourceryConfigSynthesizer(
        configPath: configFilePath,
        sourceRoots: sourceRoots,
        shippedTemplatesDirectory: context.shippedTemplatesDirectory,
        generatedFilesDir: outputDir,
        testableDefault: target.testableDefault,
        environmentVars: environmentVars)
      let result = synthesizer.synthesize(original)

      result.remarks.forEach { Diagnostics.remark($0) }
      result.warnings.forEach { Diagnostics.warning($0) }
      errors.append(contentsOf: result.errors)

      for stem in result.generatedFileStems {
        if let owner = stemOwners[stem], owner != configFilePath {
          errors.append("\(owner.lastComponent) and \(configFilePath.lastComponent) both generate '\(stem).generated.swift' onto this target's compile path, so the two would declare the same types. Give the target one config per template, or split them across targets.")
        } else {
          stemOwners[stem] = configFilePath
        }
      }

      let synthesizedPath = synthesizedConfigsDir.appending(fileName)
      // Written only when the bytes changed: the prebuild command re-runs on every
      // build, and rewriting an identical file for no reason is noise (§1.5).
      let existing = try? String(contentsOfFile: synthesizedPath.string, encoding: .utf8)
      if existing != result.text {
        try result.text.write(toFile: synthesizedPath.string, atomically: true, encoding: .utf8)
      }
      runnableConfigs.append(RunnableConfig(
        original: configFilePath,
        synthesized: synthesizedPath,
        outputDir: outputDir,
        environmentVars: environmentVars))
    }

    guard errors.isEmpty else {
      errors.forEach { Diagnostics.error("Target \"\(target.name)\": \($0)") }
      throw SourcerySwiftCodegenPluginError.configurationRejected(target: target.name, reasons: errors)
    }

    return runnableConfigs.map { config in
      let command = Self._createCommand(
        context: context,
        target: target,
        displayConfigName: config.original.lastComponent,
        configFilePath: config.synthesized,
        sourcery: sourcery,
        perTargetCachesFilesDir: perTargetCachesFilesDir,
        perTargetBuildDir: perTargetBuildDir,
        environmentVars: config.environmentVars,
        generatedFilesDir: config.outputDir)

      Diagnostics.remark("\(command)")

      return command
    }
  }

#if compiler(>=6.0)
  private static func _createCommand(
    context: CodegenPluginContext,
    target: CodegenPluginTarget,
    displayConfigName: String,
    configFilePath: Path,
    sourcery: Path,
    perTargetCachesFilesDir: Path,
    perTargetBuildDir: Path,
    environmentVars: [String: String],
    generatedFilesDir: Path
  ) -> Command {
    Command.prebuildCommand(
      displayName: "Target \(target.name): running Sourcery with config: \(displayConfigName)",
      executable: sourcery,
      arguments: [
        "--config",
        configFilePath.string,
        "--cacheBasePath",
        perTargetCachesFilesDir.string,
        "--buildPath",
        perTargetBuildDir.string,
        "--verbose",
      ],
      environment: environmentVars,
      outputFilesDirectory: generatedFilesDir
    )
  }
#else
  private static func _createCommand(
    context: CodegenPluginContext,
    target: CodegenPluginTarget,
    displayConfigName: String,
    configFilePath: Path,
    sourcery: Path,
    perTargetCachesFilesDir: Path,
    perTargetBuildDir: Path,
    environmentVars: [String: String],
    generatedFilesDir: Path
  ) -> Command {
    Command._prebuildCommand(
      displayName: "Target \(target.name): running Sourcery with config: \(displayConfigName)",
      executable: sourcery,
      arguments: [
        "--config",
        configFilePath.string,
        "--cacheBasePath",
        perTargetCachesFilesDir.string,
        "--buildPath",
        perTargetBuildDir.string,
        "--verbose",
      ],
      environment: environmentVars,
      workingDirectory: context.pluginWorkDirectory,
      outputFilesDirectory: generatedFilesDir
    )
  }
#endif
}

// MARK: - BuildToolPlugin

let rgSourcery = try! Regex("[^/:]*\\.sourcery([^/:]*)\\.yml$").ignoresCase()

func wrap(_ target: PackagePlugin.Target, in package: PackagePlugin.Package) -> TargetWrapper {
  TargetWrapper(target, rootPackage: package)
}

extension PackagePlugin.PluginContext: CodegenPluginContext {
  var rootDirectory: PackagePlugin.Path { `package`.directory }

  /// The `templates/` directory of whichever package in the graph is this one
  /// (§4.5). Breadth-first and deduplicated by package id, because a consumer may
  /// reach this package through a shared first-party one rather than declaring it
  /// directly.
  ///
  /// The spec proposed matching on the plugin *target's* name. That is not
  /// available: `Package.targets` exposes source-module, binary-artifact and
  /// system-library targets only — a plugin target never appears in it, so the
  /// match would never fire. `displayName` is the manifest's own `name:`, which
  /// serves the same purpose the target name was chosen for: it is written in this
  /// repository, not in the consumer's, so vendoring the package under another
  /// directory name changes the identity and leaves the match intact. The
  /// `templates/` directory has to be there too, so a consumer package that
  /// happens to share the name cannot be mistaken for this one.
  var shippedTemplatesDirectory: PackagePlugin.Path? {
    var seen = Set<Package.ID>()
    var queue: [Package] = [`package`]
    while !queue.isEmpty {
      let current = queue.removeFirst()
      guard seen.insert(current.id).inserted else { continue }
      if current.displayName == pluginPackageName || current.id == pluginPackageIdentity {
        let templates = current.directory.appending("templates")
        if templates.isDirectory { return templates }
      }
      queue.append(contentsOf: current.dependencies.map { $0.package })
    }
    return nil
  }

  var environmentVars: [String : String] {
    let environmentVars =
    [
      "GIT_ROOT": gitRootDirectory(rootDirectory),
      "SOURCERY_PACKAGE": rootDirectory.string, // For SPM packages
    ].merging(`package`.targets.flatMap { t in
        [
          ("SOURCERY_TARGET_\(t.name)", t.directory.string)
        ] + t.dependencies.flatMap { (d: TargetDependency) in
          d.dependencyInfoArray.map {
            ("SOURCERY_TARGET_\(t.name)_DEP_\($0.0)", $0.1.string)
          }
        }
      }, uniquingKeysWith: { (a, _) in a })

    return environmentVars
  }
}

extension TargetDependency {
  var dependencyInfoArray: [(String, Path)] {
    switch self {
    case let .target(target):
      return [(target.name, target.directory)]

    case let .product(product):
      return product.sourceModules.map {
        ("\(product.name)_MODULE_\($0.moduleName)", $0.directory)
      } + product.targets.map {
        ("\(product.name)_TARGET_\($0.name)", $0.directory)
      }

    @unknown default:
      fatalError("Unknown TargetDependency value: \(self)")
    }
  }
}

struct TargetWrapper: CodegenPluginTarget {
  let wrapped: PackagePlugin.Target
  let rootPackage: PackagePlugin.Package
  init(_ target: PackagePlugin.Target, rootPackage: PackagePlugin.Package) {
    self.wrapped = target
    self.rootPackage = rootPackage
  }

  var name: String { wrapped.name }
  func sourceryConfigFileLocations(rootDirectory: PackagePlugin.Path) -> Set<Path> {
    [wrapped.directory]
  }

  /// §3.1. `recursiveTargetDependencies` is the transitive closure and does not
  /// include the receiver, so the target's own directory is prepended.
  /// `compactMap { $0.sourceModule }` drops binary targets, system libraries and
  /// plugin targets; `.macro` and `.snippet` are filtered out because a macro
  /// target's sources are compiler-plugin code and a snippet is not part of the
  /// module surface — neither can contribute a protocol a mock is generated from.
  var derivedSourceRoots: [Path] {
    let modules: [any SourceModuleTarget] =
      ([wrapped] + wrapped.recursiveTargetDependencies).compactMap { $0.sourceModule }
    return normalizedSourceRoots(
      modules
        .filter { $0.kind == .generic || $0.kind == .executable || $0.kind == .test }
        .map { $0.directory })
  }

  /// §4.6, D11: the candidates are the test target's *direct* `.target`
  /// dependencies whose module is in the root package and is not itself a test
  /// module. The module a test target tests is the one it depends on; a module it
  /// reaches only through that one is not, and restricting to `.target` keeps
  /// first-party modules from other packages out.
  var testableDefault: TestableDefault {
    guard let module = wrapped.sourceModule, module.kind == .test else { return .notApplicable }
    let rootPackageTargetNames = Set(rootPackage.targets.map { $0.name })
    var candidates: [String] = []
    for dependency in wrapped.dependencies {
      guard case let .target(dependencyTarget) = dependency,
            rootPackageTargetNames.contains(dependencyTarget.name),
            let dependencyModule = dependencyTarget.sourceModule,
            dependencyModule.kind != .test,
            !candidates.contains(dependencyModule.moduleName)
      else { continue }
      candidates.append(dependencyModule.moduleName)
    }
    if candidates.count == 1 { return .unambiguous(candidates[0]) }
    return .ambiguous(candidates.sorted())
  }
}

extension SourcerySwiftCodegenPlugin: PackagePlugin.BuildToolPlugin {
  func createBuildCommands(context: PackagePlugin.PluginContext, target: PackagePlugin.Target) throws -> [Command] {
    return try _createBuildCommands(context: context, target: wrap(target, in: context.package))
  }
}

// MARK: - XcodeProjectPlugin

#if canImport(XcodeProjectPlugin)

import XcodeProjectPlugin

extension XcodeProjectPlugin.XcodePluginContext: CodegenPluginContext {
  var rootDirectory: PackagePlugin.Path { xcodeProject.directory }

  /// §3.4, §4.5: `XcodePluginContext` exposes no package graph, so there is
  /// nothing to find the shipped templates in. A bare template name warns and
  /// fails; Xcode consumers keep naming templates by path.
  var shippedTemplatesDirectory: PackagePlugin.Path? { nil }

  var environmentVars: [String : String] {
    let environmentVars =
    [
      "GIT_ROOT": gitRootDirectory(rootDirectory),
      "SOURCERY_PROJECT": rootDirectory.string,
    ].merging(xcodeProject.targets.flatMap { t in
      // Diagnostics.warning("### Target '\(t.name)' dependencies: \(t.dependencies)")
      return t.dependencies.flatMap { (d: XcodeTargetDependency) in
        d.dependencyInfoArray.map {
          ("SOURCERY_TARGET_\(t.name)_DEP_\($0.0)", $0.1.string)
        }
      }
    }, uniquingKeysWith: { (a, _) in a })

    return environmentVars
  }
}

extension XcodeTargetDependency {
  var dependencyInfoArray: [(String, Path)] {
    switch self {
    case .target(_):
      // Diagnostics.warning("### Dependency target: \(target.name)")
      return []

    case let .product(product):
      // Diagnostics.warning("### Dependency product: \(product.name)")
      return product.sourceModules.map {
        ("\(product.name)_MODULE_\($0.moduleName)", $0.directory)
      } + product.targets.map {
        ("\(product.name)_TARGET_\($0.name)", $0.directory)
      }

    @unknown default:
      fatalError("Unknown TargetDependency value: \(self)")
    }
  }
}

extension XcodeProjectPlugin.XcodeTarget: CodegenPluginTarget {
  var name: String { displayName }
  func sourceryConfigFileLocations(rootDirectory: PackagePlugin.Path) -> Set<Path> {
    let rootDirectoryComponents = rootDirectory.components
    // return one level deep locations relative to the rootDirectory
    let inputLocations = Set(inputFiles.map { $0.path.removingLastComponent() })
    return Set(inputLocations.flatMap { path -> [Path] in
      let components = path.components
      guard components.starts(with: rootDirectoryComponents) else {
        return []
      }

      var res: [Path] = []
      if components.count > rootDirectoryComponents.count {
        res.append(rootDirectory.appending(components[rootDirectoryComponents.count]))
      }
      return res
    })
  }

  /// The placeholder expands to the target's own input-file directories, and to
  /// nothing else. `XcodeTarget` has no `recursiveTargetDependencies`, and
  /// `dependencies` was measured empty on Xcode 26.5 for a package product
  /// dependency as well as for a sibling target, so `productDirectories` below is
  /// always empty in practice (001 follow-up §1.3, which obsoletes 001 §3.4's
  /// claim that the product modules are reached). It is kept rather than deleted
  /// because it costs nothing and becomes correct if the API starts reporting
  /// dependency edges; `run-xcode-checks.sh`'s **closure** gate is what reports
  /// that change. Until then an author names any further directory in `sources:`
  /// with `${SOURCERY_PROJECT}`, and the README says so.
  var derivedSourceRoots: [Path] {
    let inputDirectories = inputFiles
      .filter { $0.type == .source }
      .map { $0.path.removingLastComponent() }
    let productDirectories = dependencies.flatMap { $0.dependencyInfoArray.map { $0.1 } }
    return normalizedSourceRoots(inputDirectories + productDirectories)
  }

  /// No package graph, so no way to tell a root-package module from any other.
  var testableDefault: TestableDefault { .notApplicable }
}

extension PackagePlugin.Path {
  var components: [String] {
    let prev = removingLastComponent()
    guard !prev.string.isEmpty && prev.string != "/" else { return [lastComponent] }
    return prev.components + [lastComponent]
  }
}

extension SourcerySwiftCodegenPlugin: XcodeBuildToolPlugin {
  func createBuildCommands(context: XcodeProjectPlugin.XcodePluginContext, target: XcodeProjectPlugin.XcodeTarget) throws -> [Command] {
    return try _createBuildCommands(context: context, target: target)
  }
}

#endif

// MARK: - Internal

extension String {
  func matches(_ regex: Regex<AnyRegexOutput>) -> Bool {
    guard let m = wholeMatch(of: regex) else { return false }
    return !m.isEmpty
  }
}

extension Path {
  var fileExists: Bool {
    FileManager.default.fileExists(atPath: string)
  }

  var isDirectory: Bool {
    var result: ObjCBool = false
    FileManager.default.fileExists(atPath: string, isDirectory: &result)
    return result.boolValue
  }

  var isExecutable: Bool {
    FileManager.default.isExecutableFile(atPath: string)
  }
}
