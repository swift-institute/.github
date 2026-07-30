// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        // The ruled exception covers only "main" — any other branch on an
        // Institute-owned dependency is still a moving target and fails.
        .package(url: "https://github.com/swift-primitives/swift-example.git", branch: "feature/x"),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
