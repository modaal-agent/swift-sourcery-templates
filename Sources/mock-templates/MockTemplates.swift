import ArgumentParser

@main
struct MockTemplates: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mock-templates",
    abstract: "Fingerprinted code generation over the mock templates.",
    discussion: """
      `generate` runs the Sourcery engine and writes the output under a \
      fingerprint block: the bundle tag, the generator config, the path and \
      SHA-256 of every scanned source file, and the hash of the generated \
      body. `validate` re-hashes that list and the body — no engine run, no \
      template compile — so a cold CI job can prove a committed file current \
      in seconds. `imprint` refreshes the block without regenerating.

      The tool is policy-free: which sources to scan, which template drives \
      a file and which bundle tag to expect are the calling script's to \
      decide.
      """,
    subcommands: [Generate.self, Imprint.self, Validate.self]
  )
}
