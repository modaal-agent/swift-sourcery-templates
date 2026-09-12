// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "SourcerySwiftCodegen",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .plugin(name: "SourcerySwiftCodegenPlugin", targets: ["SourcerySwiftCodegenPlugin"]),
    .executable(name: "mock-templates", targets: ["mock-templates"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
  ],
  targets: [
    // This repository's own artifact bundle rather than upstream Sourcery's.
    // It carries the same engine — Scripts/engine-pin.sh is the upstream pin the
    // release lane vendors from, and the bundle's info.json declares the
    // artifact `sourcery` at that version, so `context.tool(named: "sourcery")`
    // resolves exactly as before. What it adds is `templates/` beside the
    // executable, which is the plugin's third route to a shipped template and
    // the only one available to an Xcode project that reaches this package
    // through neither a package graph nor this checkout
    // (specs/001-plugin-source-discovery/followup-xcode-lane.md §12, §18 step 3).
    //
    // The asset has to exist before this commit references it, so it is
    // published by a `templates-X.Y.Z` tag and this pin lands after it;
    // Scripts/check-pinned-templates.sh refuses a release whose pinned
    // templates/ is not the commit's.
    .binaryTarget(
      name: "sourcery",
      url: "https://github.com/modaal-agent/swift-sourcery-templates/releases/download/templates-0.9.0/swift-sourcery-templates-0.9.0.artifactbundle.zip",
      checksum: "e2b4e8c92e4afb10e0d1ce94aab04ea6a1dfbf5a7c6d75fa77b6418266b7af8d"
    ),
    .plugin(
      name: "SourcerySwiftCodegenPlugin",
      capability: .buildTool,
      dependencies: ["sourcery"]
    ),
    .executableTarget(
      name: "mock-templates",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
  ]
)
