// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        // A branch pin on a NON-Institute org is outside this rule's scope.
        .package(url: "https://github.com/apple/swift-nio.git", branch: "main"),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
