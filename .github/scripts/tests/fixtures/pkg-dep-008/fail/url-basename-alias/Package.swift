// swift-tools-version: 6.0
import PackageDescription

// The live-incident shape: dir `swift-windows-32`, origin `swift-windows-standard.git`.
let package = Package(
    name: "fixture-url-basename-alias",
    dependencies: [
        .package(url: "https://github.com/swift-microsoft/swift-windows-standard.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Fixture",
            dependencies: [
                .product(name: "Windows", package: "swift-windows-32"),
            ]
        ),
    ]
)
