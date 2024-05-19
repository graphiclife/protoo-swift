// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "protoo-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "protoo-client", targets: ["protoo-client"]),
    ],
    dependencies: [
      .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
      .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
      .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
    ],
    targets: [
        .target(name: "protoo-client", dependencies: [
            .product(name: "Logging", package: "swift-log"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOFoundationCompat", package: "swift-nio"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
        ]),
        .testTarget(name: "protoo-swiftTests", dependencies: ["protoo-client"]),
    ]
)
