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
            name: "CI Canon",
            targets: ["CI Canon"]
        ),
        .library(
            name: "CI Validation",
            targets: ["CI Validation"]
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
        // The documents this control plane distributes into every
        // package, and how they are spliced. One owner for the renderer
        // (`sync-gitignore.yml`) and the gate (`validate-gitignore.yml`),
        // which must never disagree about where canon ends.
        .target(
            name: "CI Canon",
            dependencies: ["CI Contract"]
        ),
        // Runs rule predicates over a repository. Wave-1 port peers add
        // one validator file each here, plus one line in
        // `CI.Validation.Registry`.
        .target(
            name: "CI Validation",
            dependencies: ["CI Contract", "CI Workflow", "CI Canon"]
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
                "CI Workflow",
                "CI Canon",
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
            name: "CI Canon Tests",
            dependencies: ["CI Canon"]
        ),
        .testTarget(
            name: "CI Validation Tests",
            dependencies: ["CI Validation"]
        ),
        .testTarget(
            name: "Institute Receipt Tests",
            dependencies: ["Institute Receipt"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
