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
            name: "CI Symbol Graph",
            targets: ["CI Symbol Graph"]
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
        // Umbrella symbol-graph preparation for the DocC pipeline.
        .target(
            name: "CI Symbol Graph",
            dependencies: ["CI Contract"]
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
                "CI Symbol Graph",
                "CI Validation",
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
            name: "CI Symbol Graph Tests",
            dependencies: ["CI Symbol Graph"]
        ),
        // Positive controls over the shell embedded in shipped
        // workflows and composite actions. The subject is the shipped
        // bytes, extracted by name through `CI Workflow`.
        .testTarget(
            name: "Embedded Shell Tests",
            dependencies: ["CI Workflow"]
        ),
        .testTarget(
            name: "Institute Receipt Tests",
            dependencies: ["Institute Receipt"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
