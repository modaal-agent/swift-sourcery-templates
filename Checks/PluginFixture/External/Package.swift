// swift-tools-version: 5.9
import PackageDescription

// A separate package, so `ExternalKit` reaches `App` the way a checkout does:
// through a dependency of a dependency, with no env var naming it.
let package = Package(
  name: "ExternalFixtureKit",
  products: [
    .library(name: "ExternalKit", targets: ["ExternalKit"]),
  ],
  targets: [
    .target(name: "ExternalKit"),
  ]
)
