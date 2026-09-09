// swift-tools-version: 5.9
import PackageDescription

// The black-box fixture for the build-tool plugin. A plugin target cannot be
// imported by a test target (spec 001 §1.5), so everything the plugin does is
// checked by building this package and reading what it wrote:
// Checks/run-plugin-checks.sh.
//
// The shape that matters is the chain App → Middle → Leaf, with ExternalKit
// arriving through Middle from a second package. `Leaf` and `ExternalKit` are two
// levels from `App`, which is exactly the distance no `SOURCERY_TARGET_*` var can
// reach.
let package = Package(
  name: "PluginFixture",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(name: "swift-sourcery-templates", path: "../.."),
    .package(name: "ExternalFixtureKit", path: "External"),
  ],
  targets: [
    .target(name: "Leaf"),
    .target(
      name: "Middle",
      dependencies: [
        "Leaf",
        .product(name: "ExternalKit", package: "ExternalFixtureKit"),
      ]
    ),
    // The placeholder shape: the closure plus one hand-listed entry, and two
    // shipped templates named by name from one config (§4.7).
    .target(
      name: "App",
      dependencies: ["Middle"],
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
    // The zero-configuration shape: `templates:` and nothing else.
    .target(
      name: "Solo",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
    // The shape that must come out byte-identical.
    .target(
      name: "Verbatim",
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
    // A template beside the config wins over the shipped one of the same name.
    // Excluded from the target's sources because SwiftPM has no rule for it.
    .target(
      name: "Local",
      exclude: ["Mocks.swifttemplate"],
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
    // One direct root-package dependency: `args.testable` is unambiguous.
    .testTarget(
      name: "AppTests",
      dependencies: ["App"],
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
    // Two: the plugin inserts nothing and names both.
    .testTarget(
      name: "AmbiguousTests",
      dependencies: ["App", "Solo"],
      plugins: [.plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")]
    ),
  ]
)
