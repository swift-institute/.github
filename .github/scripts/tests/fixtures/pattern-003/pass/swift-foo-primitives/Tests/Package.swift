// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-foo-primitives-tests",
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing", branch: "main"),
    ],
    targets: [
        .testTarget(name: "Foo Primitives Tests", dependencies: [
            .product(name: "Testing", package: "swift-testing"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
