// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "swift-foo-primitives",
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
    ],
    targets: [
        .target(name: "Foo Primitives"),
        .testTarget(name: "Foo Primitives Tests", dependencies: [
            "Foo Primitives",
            .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
        ]),
    ]
)
