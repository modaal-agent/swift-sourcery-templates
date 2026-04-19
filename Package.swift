// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "SourcerySwiftCodegen",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .plugin(name: "SourcerySwiftCodegenPlugin", targets: ["SourcerySwiftCodegenPlugin"])
  ],
  targets: [
    .binaryTarget(
      name: "sourcery",
      url: "https://github.com/krzysztofzablocki/Sourcery/releases/download/2.3.0/sourcery-2.3.0.artifactbundle.zip",
      checksum: "2fb2ae820c4d12f77232bacba5ee719fff9d61c71c3e8c6067691b2e90aa4ba7"
    ),
    .plugin(
      name: "SourcerySwiftCodegenPlugin",
      capability: .buildTool,
      dependencies: ["sourcery"]
    ),
  ]
)
