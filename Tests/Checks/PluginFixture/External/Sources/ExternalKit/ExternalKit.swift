// Level 3 of the chain, and in a different package: `App` reaches this only
// through `Middle`, so no `SOURCERY_TARGET_*` var can name it.
public protocol Reporting {
  func report(_ message: String)
}
