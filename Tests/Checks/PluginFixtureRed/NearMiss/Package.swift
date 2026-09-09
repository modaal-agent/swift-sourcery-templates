// swift-tools-version: 5.9
import PackageDescription

// A red control: this package must FAIL to build. Its protocol is annotated
// `/// sourcery: protocolmock`, which is not `ProtocolMock` — annotation names
// are matched exactly, including case. Before the registry that was silent: the
// key was stored, no template asked for it, generation completed, and the mock
// was simply absent from the build.
//
// One package per control, not one package with four targets: build planning runs
// every target's plugin, so a plan-time error in one target fails the build for
// all of them and no `--target` can isolate it.
let package = Package(
  name: "NearMiss",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../../../.."),
  ],
  targets: [
    .target(
      name: "NearMiss",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
