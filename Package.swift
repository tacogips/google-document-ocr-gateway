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
    .package(url: "https://github.com/tacogips/google-gateway-auth.git", revision: "13c40e24b11da9bab17046a918630fbb6aa6c147"),
    .package(url: "https://github.com/tacogips/google-service-gateway.git", revision: "6dc0261f77650eaeb09bb2ccc2890d5d83172fd0")
  ],
  targets: [
    .target(name: "AppCore", dependencies: [.product(name: "GoogleServiceGatewayCore", package: "google-service-gateway")], resources: [.copy("Resources")]),
    .executableTarget(
      name: "AppCLI",
      dependencies: [.product(name: "GoogleGatewayAuth", package: "google-gateway-auth"), "AppCore"]
    ),
    .testTarget(
      name: "AppCoreTests",
      dependencies: ["AppCore", .product(name: "GoogleServiceGatewayCore", package: "google-service-gateway")]
    )
  ],
  swiftLanguageModes: [.v6]
)
