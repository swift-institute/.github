// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-example.git", branch: "develop"),
        .package(url: "https://github.com/swift-standards/swift-other.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
