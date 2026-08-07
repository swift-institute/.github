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
            name: "CI Inventory",
            targets: ["CI Inventory"]
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
        // Describes the shipped verdict: the universal workflow's jobs,
        // postures, waves, token boundary, and single aggregate. Models
        // the terminal one-hop topology; there are no layer wrappers.
        .target(
            name: "CI Inventory",
            dependencies: ["CI Contract", "CI Workflow"]
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
                "CI Inventory",
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
            name: "CI Inventory Tests",
            dependencies: ["CI Inventory"],
            // Read from source through `#filePath`, not bundled: the
            // corpus is an expectation to regenerate and diff, and the
            // recorded run is evidence, not a resource.
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "Institute Receipt Tests",
            dependencies: [
                "Institute Receipt",
                // The installer suite reads the shipped `swift-ci.yml`
                // step through the same workflow reader every validator
                // uses, rather than a second YAML implementation.
                "CI Workflow",
                "CI Contract",
                .product(name: "Byte Primitives", package: "swift-byte-primitives"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
