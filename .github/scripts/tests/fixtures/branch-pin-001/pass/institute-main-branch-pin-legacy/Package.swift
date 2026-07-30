// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        // Legacy `.branch(` syntax carries the same ruled "main" exception
        // as the `branch:` label form.
        .package(url: "https://github.com/swift-primitives/swift-example.git", .branch("main")),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
