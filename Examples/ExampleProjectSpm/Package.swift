// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ExampleProjectSpm",
  platforms: [
    .iOS(.v13)
  ],
  products: [
    .library(name: "ExampleProjectSpm", targets: ["ExampleProjectSpm"]),
  ],
  dependencies: [
    .package(url: "https://github.com/Alamofire/Alamofire.git", "4.0.0"..<"5.0.0"),
    .package(url: "https://github.com/uber/RIBs.git", from: "0.16.1"),
    .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "6.6.0"),
    .package(url: "https://github.com/Quick/Quick.git", from: "7.3.0"),
    .package(url: "https://github.com/Quick/Nimble.git", from: "13.0.0"),
    .package(name: "swift-sourcery-templates", path: "../.."),
  ],
  targets: [
    // Two levels below the test target: `ExampleProjectSpmTests` depends on
    // `ExampleProjectSpm`, which depends on this. No env var names it, so the
    // config can only reach it through ${SOURCERY_SOURCES}.
    .target(name: "ExampleProjectSpmCore"),
    .target(
      name: "ExampleProjectSpm",
      dependencies: [
        "ExampleProjectSpmCore",
        .product(name: "Alamofire", package: "Alamofire"),
        .product(name: "RIBs", package: "RIBs"),
        .product(name: "RxSwift", package: "RxSwift"),
      ],
      plugins: [
        .plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")
      ]
    ),
    .testTarget(
      name: "ExampleProjectSpmTests",
      dependencies: [
        .product(name: "RIBs", package: "RIBs"),
        .product(name: "RxBlocking", package: "RxSwift"),
        .product(name: "RxTest", package: "RxSwift"),
        .product(name: "Quick", package: "Quick"),
        .product(name: "Nimble", package: "Nimble"),
        .target(name: "ExampleProjectSpm"),
      ],
      plugins: [
        .plugin(name: "SourcerySwiftCodegenPlugin", package: "swift-sourcery-templates")
      ]
    ),
  ]
)
