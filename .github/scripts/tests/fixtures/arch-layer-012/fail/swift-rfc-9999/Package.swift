// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "swift-rfc-9999",
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-jsonish.git", branch: "main"),
    ],
    targets: [
        .target(name: "RFC 9999"),
        .testTarget(name: "RFC 9999 Tests", dependencies: [
            "RFC 9999",
            .product(name: "Jsonish", package: "swift-jsonish"),
        ]),
    ]
)
