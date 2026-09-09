// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Kit",
  platforms: [.macOS(.v13)],
  products: [.library(name: "KitCore", targets: ["KitCore"])],
  targets: [
    .target(name: "KitLeaf"),
    .target(name: "KitCore", dependencies: ["KitLeaf"]),
  ]
)
