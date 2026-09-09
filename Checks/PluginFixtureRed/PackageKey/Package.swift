// swift-tools-version: 5.9
import PackageDescription

// A red control: this package must FAIL to build. It declares `package:` in place of `sources:`. The plugin must append no `sources:` block over it (§1.4/G, and the silent-override case of §1.4/I); Sourcery then fails on `package:`, which needs a toolchain the plugin sandbox does not give it.
//
// One package per control, not one package with four targets: build planning runs
// every target's plugin, so a plan-time error in one target fails the build for
// all of them and no `--target` can isolate it.
let package = Package(
  name: "PackageKey",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../../.."),
  ],
  targets: [
    .target(
      name: "PackageKey",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
