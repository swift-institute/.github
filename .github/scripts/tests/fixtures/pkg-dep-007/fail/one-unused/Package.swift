// swift-tools-version: 6.3.1
import PackageDescription
let package = Package(
    name: "swift-fixture-fail-one-unused",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-primitives.git", branch: "main"),
    ],
    targets: [
        .target(name: "Fixture", dependencies: [
            .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
        ]),
    ]
)
