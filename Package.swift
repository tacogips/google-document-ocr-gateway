// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "google-document-ocr",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AppCore", targets: ["AppCore"]),
    .executable(name: "google-document-ocr", targets: ["AppCLI"])
  ],
  targets: [
    .target(name: "AppCore", resources: [.copy("Resources")]),
    .executableTarget(
      name: "AppCLI",
      dependencies: ["AppCore"]
    ),
    .testTarget(
      name: "AppCoreTests",
      dependencies: ["AppCore"]
    )
  ],
  swiftLanguageModes: [.v6]
)
