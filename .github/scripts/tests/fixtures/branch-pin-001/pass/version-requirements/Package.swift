// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-example.git", from: "1.0.0"),
        .package(url: "https://github.com/swift-standards/swift-other.git", exact: "2.1.3"),
        .package(url: "https://github.com/swift-foundations/swift-third.git", .upToNextMajor(from: "0.3.0")),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
