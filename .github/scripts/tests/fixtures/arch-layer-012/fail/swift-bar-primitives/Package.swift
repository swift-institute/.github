// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "swift-bar-primitives",
    dependencies: [
        .package(url: "https://github.com/swift-standards/swift-rfc-4122.git", branch: "main"),
    ],
    targets: [
        .target(name: "Bar Primitives"),
        .testTarget(name: "Bar Primitives Tests", dependencies: [
            "Bar Primitives",
            .product(name: "UUID", package: "swift-rfc-4122"),
        ]),
    ]
)
