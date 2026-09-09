// This target ships its own Mocks.swifttemplate beside its config. Rule 2 of
// §4.5 runs before rule 3, so the local file wins over the shipped template of
// the same name and no mock is generated here at all.
// sourcery: CreateMock
protocol Shadowed {
  func shadow()
}
