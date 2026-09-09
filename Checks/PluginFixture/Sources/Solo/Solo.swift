// The zero-configuration case: one target, one annotated protocol, and a config
// that says only what to generate.
// sourcery: CreateMock
protocol Greeting {
  func greet(_ name: String) -> String
}
