/// A sibling Xcode target in the same project, carrying no plugin. It exists so
/// `Dependent` has something to depend on.
public protocol Auditing {
  func audit(_ item: String)
}
