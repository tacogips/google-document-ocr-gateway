// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "google-document-ocr-gateway",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AppCore", targets: ["AppCore"]),
    .executable(name: "google-document-ocr-gateway", targets: ["AppCLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/tacogips/google-service-gateway.git", revision: "28a86e2e06e1b57642c4c1dd37dc12fa2c8db0e4")
  ],
  targets: [
    .target(name: "AppCore", dependencies: [.product(name: "GoogleServiceGatewayCore", package: "google-service-gateway")], resources: [.copy("Resources")]),
    .executableTarget(
      name: "AppCLI",
      dependencies: ["AppCore"]
    ),
    .testTarget(
      name: "AppCoreTests",
      dependencies: ["AppCore", .product(name: "GoogleServiceGatewayCore", package: "google-service-gateway")]
    )
  ],
  swiftLanguageModes: [.v6]
)
