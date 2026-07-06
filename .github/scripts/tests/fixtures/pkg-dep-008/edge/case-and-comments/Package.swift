// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fixture-case-and-comments",
    dependencies: [
        .package(url: "https://github.com/org/swift-Example.git", branch: "main"),
        // .package(url: "https://github.com/org/swift-dead.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Fixture",
            dependencies: [
                .product(name: "Example", package: "Swift-example"),
                /* .product(name: "Dead", package: "swift-missing"), */
            ]
        ),
    ]
)
