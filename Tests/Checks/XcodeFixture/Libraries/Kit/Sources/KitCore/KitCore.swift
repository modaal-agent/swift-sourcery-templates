import KitLeaf

/// One module away from the App target, through a package product dependency.
public protocol Caching: Reporting {
  var cacheLimit: Int { get }
}
