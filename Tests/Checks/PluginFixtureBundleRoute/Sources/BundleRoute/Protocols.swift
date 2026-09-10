/// The subject of the bundle-route gate. `ferry` has to appear in the generated
/// mock, so the gate reports on the template that ran rather than on the build
/// merely succeeding.
// sourcery: CreateMock
protocol Ferrying {
  func ferry(_ item: String) -> String
}

/// The generated mock has to satisfy this, so a template that resolved to
/// nothing fails the compile instead of leaving an empty file behind.
func acceptFerrying(_ value: any Ferrying) -> String {
  value.ferry("manifest")
}
