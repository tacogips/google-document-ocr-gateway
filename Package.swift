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
    .package(url: "https://github.com/tacogips/google-gateway-auth.git", revision: "2951cd8829d94d0b16e2a3bfdca301e57bb1f862"),
    .package(url: "https://github.com/tacogips/google-service-gateway.git", revision: "e2d11843fd5afa6065ec438f8d2a0149c88f4aed")
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
