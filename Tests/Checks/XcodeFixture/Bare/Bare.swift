/// The bare-name gate's subject. `salute` has to appear in the generated mock,
/// which is what makes this a check on the template that ran rather than on the
/// build merely succeeding.
// sourcery: CreateMock
protocol Saluting {
  func salute(_ name: String) -> String
}

/// The generated mock has to satisfy this, so a template that resolved to
/// nothing fails the compile rather than leaving an empty file behind.
func acceptSaluting(_ value: any Saluting) -> String {
  value.salute("world")
}
