// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        // Ruled exception (principal, 2026-07-30; swift-mailgun-standard#13):
        // untagged Institute dependencies pin to branch "main" and pass.
        .package(url: "https://github.com/swift-primitives/swift-example.git", branch: "main"),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
