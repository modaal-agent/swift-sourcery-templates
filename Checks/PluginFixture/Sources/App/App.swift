import ExternalKit
import Leaf
import Middle

/// The §6.1 shape. `profileID` is declared here, `cacheLimit` one module away,
/// `save` two, and `report` two and in another package — so a mock that carries
/// all four proves the closure reached every level.
// sourcery: CreateMock
protocol ProfilePersisting: Caching, Reporting {
  var profileID: String { get }
}

/// The generated mock has to satisfy this, which is what turns a missing
/// inherited requirement into a compile error rather than a silent gap.
func acceptProfilePersisting(_ value: any ProfilePersisting) -> String {
  value.profileID
}
