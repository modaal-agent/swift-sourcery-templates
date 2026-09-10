import KitCore
import KitLeaf

/// 001 §6.1's shape, moved into an Xcode project: `cacheLimit` is one module
/// away in `KitCore` and `report` two, in `KitLeaf`, which `KitCore` depends on.
/// Neither is reachable through `${SOURCERY_SOURCES}` here — the plugin API
/// reports no dependency edge — so the config names the package's source
/// directory by hand, and a mock carrying all three proves it was scanned.
// sourcery: CreateMock
protocol ProfilePersisting: Caching {
  var profileID: String { get }
}

/// The generated mock has to satisfy this, which is what turns a missing
/// inherited requirement into a compile error rather than a silent gap.
func acceptProfilePersisting(_ value: any ProfilePersisting) -> String {
  value.profileID
}
