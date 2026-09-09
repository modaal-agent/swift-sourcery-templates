// swift-tools-version: 5.9
import PackageDescription

// A red control: this package must FAIL to build. Two configs of one target name the same template, so the two would put files declaring the same types on one compile path (§4.7).
//
// One package per control, not one package with four targets: build planning runs
// every target's plugin, so a plan-time error in one target fails the build for
// all of them and no `--target` can isolate it.
let package = Package(
  name: "Collision",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../../../.."),
  ],
  targets: [
    .target(
      name: "Collision",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
