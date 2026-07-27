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
    targets: [
        .target(
            name: "Repository Policy"
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
