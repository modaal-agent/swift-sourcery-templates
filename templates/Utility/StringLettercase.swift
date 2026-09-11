import Foundation

// Courtesy of https://github.com/SwiftGen/StencilSwiftKit

// Two entry points remain, both called only from `Mocks/MockNaming.swift` and
// both only by the return-type discriminator that disambiguates overloads
// differing in return type alone. `lowercasedFirstWord`, `lowercasedFirstLetter`
// and `snakeCased` went with the prefix transform they served
// (`specs/004-mock-member-naming/spec.md` §2.1, P2); `lowerFirstWord` is the one
// that traps on an all-uppercase name — it indexes `scalars[idx]` before testing
// `idx` against `endIndex`, so `func ID()` crashed generation with "String index
// is out of bounds" (§1.2).
extension String {
    func uppercasedFirstLetter() -> String {
      return FiltersStrings.upperFirstLetter(self)
    }
    func camelCased(stripLeading: Bool = false) -> String {
      return FiltersStrings.snakeToCamelCase(self, stripLeading: stripLeading)
    }
}

private final class FiltersStrings {
  /// Uppers the first letter of the string
  /// e.g. "people picker" gives "People picker", "sports Stats" gives "Sports Stats"
  ///
  /// - Parameters:
  ///   - value: the value to uppercase first letter of
  ///   - arguments: the arguments to the function; expecting zero
  /// - Returns: the string with first letter being uppercased
  static func upperFirstLetter(_ string: String) -> String {
    return _upperFirstLetter(string)
  }

  /// Converts snake_case to camelCase, stripping prefix underscores if needed
  ///
  /// - Parameters:
  ///   - string: the value to be processed
  ///   - stripLeading: if false, will preserve leading underscores
  /// - Returns: the camel case string
  static func snakeToCamelCase(_ string: String, stripLeading: Bool) -> String {
    let unprefixed: String
    if containsAnyLowercasedChar(string) {
        let comps = string.components(separatedBy: "_")
        unprefixed = comps.map { upperFirstLetter($0) }.joined(separator: "")
    } else {
        let comps = snakecase(string).components(separatedBy: "_")
        unprefixed = comps.map { $0.capitalized }.joined(separator: "")
    }

    // only if passed true, strip the prefix underscores
    var prefixUnderscores = ""
    var result: String { return prefixUnderscores + unprefixed }
    if stripLeading {
        return result
    }
    for scalar in string.unicodeScalars {
        guard scalar == "_" else { break }
        prefixUnderscores += "_"
    }
    return result
  }

  // MARK: - Private
  private static func containsAnyLowercasedChar(_ string: String) -> Bool {
    let lowercaseCharRegex = try! NSRegularExpression(pattern: "[a-z]", options: .dotMatchesLineSeparators)
    let fullRange = NSRange(location: 0, length: string.unicodeScalars.count)
    return lowercaseCharRegex.firstMatch(in: string, options: .reportCompletion, range: fullRange) != nil
  }

  /// Uppers the first letter of the string
  /// e.g. "people picker" gives "People picker", "sports Stats" gives "Sports Stats"
  ///
  /// - Parameters:
  ///   - value: the value to uppercase first letter of
  ///   - arguments: the arguments to the function; expecting zero
  /// - Returns: the string with first letter being uppercased
  private static func _upperFirstLetter(_ string: String) -> String {
    guard let first = string.unicodeScalars.first else { return string }
    return String(first).uppercased() + String(string.unicodeScalars.dropFirst())
  }

  /// This returns the snake cased variant of the string.
  ///
  /// - Parameter string: The string to snake_case
  /// - Returns: The string snake cased from either snake_cased or camelCased string.
  private static func snakecase(_ string: String) -> String {
    let longUpper = try! NSRegularExpression(pattern: "([A-Z\\d]+)([A-Z][a-z])", options: .dotMatchesLineSeparators)
    let camelCased = try! NSRegularExpression(pattern: "([a-z\\d])([A-Z])", options: .dotMatchesLineSeparators)

    let fullRange = NSRange(location: 0, length: string.unicodeScalars.count)
    var result = longUpper.stringByReplacingMatches(in: string,
                                                    options: .reportCompletion,
                                                    range: fullRange,
                                                    withTemplate: "$1_$2")
    result = camelCased.stringByReplacingMatches(in: result,
                                                 options: .reportCompletion,
                                                 range: fullRange,
                                                 withTemplate: "$1_$2")
    return result.replacingOccurrences(of: "-", with: "_")
  }
}
