// swift-tools-version: 5.9
import PackageDescription

// The fixture for route 3 of specs/001-plugin-source-discovery/followup-xcode-lane.md
// §12: the plugin reading `templates/` out of the artifact bundle `Package.swift`
// pins.
//
// Every other fixture reaches this repository directly, so the plugin's own
// source file sits in a checkout that carries `templates/` and route 2
// (`#filePath`, up three components) always answers first. Route 3 is the
// fallback for the two undocumented behaviours route 2 rests on, so the only way
// to run it is to make route 2 fail.
//
// `../../../.build/plugin-checks/engine-package` is that: a copy of this
// repository holding Package.swift, Plugins/ and Sources/ and **no templates/**,
// which `run-plugin-checks.sh` writes before building this package. So route 1
// finds the package in the graph and no `templates/` under it, route 2 finds no
// `templates/` beside the plugin source, and route 3 answers out of the
// artifact bundle the copied manifest pins. Generated, not committed, because
// what it is is "this repository minus one directory" and a second copy in the
// tree would be a second thing to keep in step.
let package = Package(
  name: "PluginFixtureBundleRoute",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../../../.build/plugin-checks/engine-package"),
  ],
  targets: [
    .target(
      name: "BundleRoute",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
