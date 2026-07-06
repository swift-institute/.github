// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "swift-spm-fixture-standard",
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-jsonish.git", branch: "main"),
    ],
    targets: [
        .target(name: "SPM Fixture"),
        .testTarget(name: "SPM Fixture Sanctioned Tests", dependencies: [
            "SPM Fixture",
            .product(name: "Jsonish", package: "swift-jsonish"),
        ]),
    ]
)
