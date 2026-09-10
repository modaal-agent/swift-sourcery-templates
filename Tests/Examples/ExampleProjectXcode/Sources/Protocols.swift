/// What an adopter annotates.
// sourcery: CreateMock
protocol Uploading {
  func upload(_ path: String) async throws -> String
}

/// The generated mock has to satisfy this, so a template that resolved to
/// nothing fails the compile rather than leaving an empty file behind.
func acceptUploading(_ value: any Uploading) -> any Uploading {
  value
}
