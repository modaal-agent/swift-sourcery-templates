import Core

/// Self-contained on purpose: the gate here is the target's dependency on a
/// sibling Xcode target, not what the closure reaches. `Core` arrives in this
/// target's `inputFiles` as `<project>/build/Debug/Core.framework`, and the
/// plugin derives `<project>/build` from it as a place to look for configs.
// sourcery: CreateMock
protocol Dispatching {
  func dispatch(_ item: String)
}

/// Makes the dependency on `Core` real rather than declared.
func acceptAuditing(_ value: any Auditing) {
  value.audit("dependent")
}
