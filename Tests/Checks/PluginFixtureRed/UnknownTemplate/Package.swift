// swift-tools-version: 5.9
import PackageDescription

// A red control: this package must FAIL to build. Its `templates:` entry names neither a file beside the config nor a shipped template: the plugin warns and Sourcery then fails on it, which is the right outcome for a typo (§4.5 rule 4).
//
// One package per control, not one package with four targets: build planning runs
// every target's plugin, so a plan-time error in one target fails the build for
// all of them and no `--target` can isolate it.
let package = Package(
  name: "UnknownTemplate",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../../../.."),
  ],
  targets: [
    .target(
      name: "UnknownTemplate",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
