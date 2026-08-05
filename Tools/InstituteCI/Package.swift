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
    targets: [
        .target(
            name: "CI Contract"
        ),
        .target(
            name: "Institute Receipt"
        ),
        .executableTarget(
            name: "Institute CI Command",
            dependencies: ["CI Contract"]
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
