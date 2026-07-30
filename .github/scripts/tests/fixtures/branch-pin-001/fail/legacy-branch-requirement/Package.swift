// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-example.git", .branch("main")),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
