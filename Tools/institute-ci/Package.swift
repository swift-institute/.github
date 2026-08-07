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
            name: "CI Workflow",
            targets: ["CI Workflow"]
        ),
        .library(
            name: "CI Validation",
            targets: ["CI Validation"]
        ),
        .library(
            name: "Canon",
            targets: ["Canon"]
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
        // Reads an Actions workflow file into a typed document.
        .target(
            name: "CI Workflow",
            dependencies: ["CI Contract"]
        ),
        // Runs rule predicates over a repository. Wave-1 port peers add
        // one validator file each here, plus one line in
        // `CI.Validation.Registry`.
        .target(
            name: "CI Validation",
            dependencies: ["CI Contract", "CI Workflow"]
        ),
        // The rulebook checking itself: referential integrity of the
        // markdown skill corpus. No dependency on the CI contract — its
        // subject is prose, not workflows.
        .target(
            name: "Canon"
        ),
        .target(
            name: "Institute CI Application",
            dependencies: ["CI Contract", "CI Validation", "Institute Receipt"]
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
                "CI Validation",
                "Canon",
                "CI Workflow",
                "Institute Receipt",
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
            ]
        ),
        .testTarget(
            name: "CI Contract Tests",
            dependencies: ["CI Contract"]
        ),
        .testTarget(
            name: "CI Workflow Tests",
            dependencies: ["CI Workflow"]
        ),
        .testTarget(
            name: "CI Validation Tests",
            dependencies: ["CI Validation"]
        ),
        .testTarget(
            name: "Institute Receipt Tests",
            dependencies: ["Institute Receipt"]
        ),
        .testTarget(
            name: "Canon Tests",
            dependencies: ["Canon"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
