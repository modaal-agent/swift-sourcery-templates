// Level 3 of the first-party chain. No annotation here: this module is not
// scanned by a plugin that exports one level of the graph, which is the whole
// point of the fixture.
public protocol Persisting {
  func save(_ value: String, key: String) throws
}
