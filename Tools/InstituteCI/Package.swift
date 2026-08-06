// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Institute CI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "CI Contract",
            targets: ["CI Contract"]
        ),
        .library(
            name: "Institute Receipt",
            targets: ["Institute Receipt"]
        ),
        .executable(
            name: "institute-ci",
            targets: ["Institute CI Command"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-standards/swift-fips-180-4.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-byte-primitives.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "CI Contract"
        ),
        .target(
            name: "Institute CI Application",
            dependencies: ["CI Contract", "Institute Receipt"]
        ),
        .target(
            name: "Institute Receipt",
            dependencies: [
                .product(name: "FIPS 180-4", package: "swift-fips-180-4"),
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
            ]
        ),
        .executableTarget(
            name: "Institute CI Command",
            dependencies: [
                "Institute CI Application",
                "Institute Receipt",
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
            ]
        ),
        .testTarget(
            name: "CI Contract Tests",
            dependencies: ["CI Contract"]
        ),
        .testTarget(
            name: "Institute Receipt Tests",
            dependencies: ["Institute Receipt"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
