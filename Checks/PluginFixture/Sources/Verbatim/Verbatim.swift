// The config beside this target names every path itself, so the synthesized copy
// must come out byte-identical to it.
// sourcery: CreateMock
protocol Counting {
  var count: Int { get }
}
