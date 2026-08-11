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
            name: "CI Inventory",
            targets: ["CI Inventory"]
        ),
        .library(
            name: "CI Symbol Graph",
            targets: ["CI Symbol Graph"]
        ),
        .library(
            name: "Rulebook",
            targets: ["Rulebook"]
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
        // Describes the shipped verdict: the universal workflow's jobs,
        // postures, waves, token boundary, and single aggregate. Models
        // the terminal one-hop topology; there are no layer wrappers.
        .target(
            name: "CI Inventory",
            dependencies: ["CI Contract", "CI Workflow"]
        ),
        // Umbrella symbol-graph preparation for the DocC pipeline.
        .target(
            name: "CI Symbol Graph",
            dependencies: ["CI Contract"]
        ),
        // The rulebook checking itself: referential integrity of the
        // markdown skill corpus. Not `CI.Canon`, which owns the canonical
        // documents this control plane distributes — a different domain
        // that happens to share the retired script's word. No dependency
        // on the CI contract: the subject is prose, not workflows.
        .target(
            name: "Rulebook"
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
                "Rulebook",
                "Institute CI Application",
                "CI Symbol Graph",
                "CI Validation",
                "CI Workflow",
                "CI Canon",
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
            name: "Institute CI Application Tests",
            dependencies: [
                .target(name: "Institute CI Application"),
                .target(name: "Institute Receipt"),
            ]
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
            name: "CI Inventory Tests",
            dependencies: ["CI Inventory"],
            // Read from source through `#filePath`, not bundled: the
            // corpus is an expectation to regenerate and diff, and the
            // recorded run is evidence, not a resource.
            exclude: ["Fixtures"]
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
            name: "Rulebook Tests",
            dependencies: ["Rulebook"]
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
