import CryptoKit
import Foundation

/// The provenance block a generated file carries at byte 0. Every line is a
/// `//` comment, LF-terminated, so the block is inert Swift source:
///
///     // mock-templates:fingerprint v1
///     // bundle: 0.6.0
///     // config: sha256:<hex> template=Mocks.swifttemplate args=import=A;import=B
///     // input: sha256:<hex> Sources/Foo/Bar.swift
///     // body: sha256:<hex>
///     // mock-templates:end
///
/// The body — every byte after the end line — is the untouched generator
/// output; its hash is what catches a hand-edit. Input paths are recorded
/// relative to the caller's root and sorted, so the block is deterministic
/// for a given input set.
struct Fingerprint: Equatable {
  static let header = "// mock-templates:fingerprint v1"
  static let end = "// mock-templates:end"

  struct Input: Equatable {
    /// Root-relative path, `/`-separated.
    var path: String
    /// Lowercase-hex SHA-256 of the file's bytes.
    var hash: String
  }

  var bundle: String
  var configHash: String
  /// The human-readable half of the config line; `configHash` is the SHA-256
  /// of exactly this string, so the line is self-verifying.
  var configDescription: String
  var inputs: [Input]
  var bodyHash: String

  func rendered() -> String {
    var lines = [
      Self.header,
      "// bundle: \(bundle)",
      "// config: sha256:\(configHash) \(configDescription)",
    ]
    for input in inputs {
      lines.append("// input: sha256:\(input.hash) \(input.path)")
    }
    lines.append("// body: sha256:\(bodyHash)")
    lines.append(Self.end)
    return lines.joined(separator: "\n") + "\n"
  }

  /// Splits a file into its fingerprint block and the body below it.
  /// Returns nil when the file does not start with a v1 block.
  static func parse(_ data: Data) throws -> (fingerprint: Fingerprint, body: Data)? {
    guard data.starts(with: Data((header + "\n").utf8)) else { return nil }
    let endLine = Data(("\n" + end + "\n").utf8)
    guard let endRange = data.firstRange(of: endLine) else {
      throw FingerprintError.truncatedBlock
    }
    let body = data.subdata(in: endRange.upperBound..<data.endIndex)
    guard let blockText = String(data: data.subdata(in: data.startIndex..<endRange.lowerBound), encoding: .utf8) else {
      throw FingerprintError.malformed("the block is not UTF-8")
    }

    var bundle: String?
    var configHash: String?
    var configDescription: String?
    var inputs: [Input] = []
    var bodyHash: String?
    for line in blockText.split(separator: "\n").dropFirst() {
      if let rest = line.removingPrefix("// bundle: ") {
        bundle = rest
      } else if let rest = line.removingPrefix("// config: sha256:") {
        let parts = rest.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { throw FingerprintError.malformed(String(line)) }
        configHash = String(parts[0])
        configDescription = String(parts[1])
      } else if let rest = line.removingPrefix("// input: sha256:") {
        let parts = rest.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { throw FingerprintError.malformed(String(line)) }
        inputs.append(Input(path: String(parts[1]), hash: String(parts[0])))
      } else if let rest = line.removingPrefix("// body: sha256:") {
        bodyHash = rest
      } else {
        throw FingerprintError.malformed(String(line))
      }
    }
    guard let bundle, let configHash, let configDescription, let bodyHash else {
      throw FingerprintError.malformed("a required line (bundle, config, body) is missing")
    }
    let fingerprint = Fingerprint(
      bundle: bundle,
      configHash: configHash,
      configDescription: configDescription,
      inputs: inputs,
      bodyHash: bodyHash
    )
    return (fingerprint, body)
  }
}

enum FingerprintError: Error, CustomStringConvertible {
  case truncatedBlock
  case malformed(String)

  var description: String {
    switch self {
    case .truncatedBlock:
      return "the fingerprint block has no end marker (\(Fingerprint.end))"
    case .malformed(let line):
      return "malformed fingerprint line: \(line)"
    }
  }
}

extension Substring {
  fileprivate func removingPrefix(_ prefix: String) -> String? {
    guard hasPrefix(prefix) else { return nil }
    return String(dropFirst(prefix.count))
  }
}

func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func sha256Hex(fileAt path: String) throws -> String {
  sha256Hex(try Data(contentsOf: URL(fileURLWithPath: path)))
}
