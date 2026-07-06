// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "swift-jsonish",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
    ],
    targets: [
        .target(name: "Jsonish"),
        .testTarget(name: "Jsonish Tests", dependencies: [
            "Jsonish",
            .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
        ]),
    ]
)
