// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "repository-policy",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "Repository Policy",
            targets: ["Repository Policy"]
        ),
        .executable(
            name: "repository-policy",
            targets: ["Repository Policy CLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-byte-primitives", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-fips-180-4", branch: "main"),
    ],
    targets: [
        .target(
            name: "Repository Policy",
            dependencies: [
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
                .product(name: "FIPS 180-4", package: "swift-fips-180-4"),
            ]
        ),
        .executableTarget(
            name: "Repository Policy CLI",
            dependencies: ["Repository Policy"]
        ),
        .testTarget(
            name: "Repository Policy Tests",
            dependencies: ["Repository Policy"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
