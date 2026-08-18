import Foundation

/// Enumeration of the files a generation run reads — the set the fingerprint
/// records and validation re-hashes. The rule, stated once: every regular
/// `.swift` file under each root (a root that is itself a `.swift` file is
/// included as-is), hidden files and directories skipped, deduplicated,
/// recorded relative to `root`, sorted by that recorded path.
enum SourceSet {
  static func enumerate(sources: [String], relativeTo root: String) throws -> [String] {
    let fileManager = FileManager.default
    var paths: Set<String> = []
    for source in sources {
      let sourceURL = URL(fileURLWithPath: source).standardizedFileURL
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
        throw SourceSetError.missingRoot(source)
      }
      if !isDirectory.boolValue {
        paths.insert(try relativize(sourceURL.path, to: root))
        continue
      }
      guard
        let enumerator = fileManager.enumerator(
          at: sourceURL,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      else {
        throw SourceSetError.missingRoot(source)
      }
      for case let url as URL in enumerator {
        guard url.pathExtension == "swift",
          try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { continue }
        paths.insert(try relativize(url.standardizedFileURL.path, to: root))
      }
    }
    return paths.sorted()
  }

  /// A recorded path must reproduce on another checkout, so it is always
  /// root-relative; a file outside the root is a caller error, not a fallback
  /// to an absolute path.
  static func relativize(_ path: String, to root: String) throws -> String {
    let rootPath = URL(fileURLWithPath: root).standardizedFileURL.path
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard path.hasPrefix(prefix) else {
      throw SourceSetError.outsideRoot(path: path, root: rootPath)
    }
    return String(path.dropFirst(prefix.count))
  }
}

enum SourceSetError: Error, CustomStringConvertible {
  case missingRoot(String)
  case outsideRoot(path: String, root: String)

  var description: String {
    switch self {
    case .missingRoot(let path):
      return "no such sources path: \(path)"
    case .outsideRoot(let path, let root):
      return "\(path) is outside the fingerprint root \(root) — pass a --root containing every source"
    }
  }
}
