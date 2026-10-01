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
    .package(url: "https://github.com/tacogips/google-gateway-auth.git", revision: "28331014f2ab9f8f02f77d068421afac105150dc"),
    .package(url: "https://github.com/tacogips/google-service-gateway.git", revision: "989ac91473e94f885a4a61be3b4512ea763186b8")
  ],
  targets: [
    .target(name: "AppCore", dependencies: [.product(name: "GoogleGatewayAuth", package: "google-gateway-auth"), .product(name: "GoogleServiceGatewayCore", package: "google-service-gateway")], resources: [.copy("Resources")]),
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
