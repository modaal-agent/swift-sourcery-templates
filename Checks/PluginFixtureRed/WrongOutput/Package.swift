// swift-tools-version: 5.9
import PackageDescription

// A red control: this package must FAIL to build. Its `output:` names a directory the build does not collect from, which the plugin rejects at plan time rather than generating into a directory nothing reads (D12).
//
// One package per control, not one package with four targets: build planning runs
// every target's plugin, so a plan-time error in one target fails the build for
// all of them and no `--target` can isolate it.
let package = Package(
  name: "WrongOutput",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../../.."),
  ],
  targets: [
    .target(
      name: "WrongOutput",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
