// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fixture-url-canonical",
    dependencies: [
        .package(url: "https://github.com/swift-microsoft/swift-windows-standard.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Fixture",
            dependencies: [
                .product(name: "Windows", package: "swift-windows-standard"),
            ]
        ),
    ]
)
