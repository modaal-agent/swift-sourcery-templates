import ExternalKit
import Leaf

// Level 2. `App` depends on this; `Leaf` and `ExternalKit` are one level deeper
// still, which is the level with no expressible workaround before spec 001.
public protocol Caching: Persisting {
  var cacheLimit: Int { get }
}
