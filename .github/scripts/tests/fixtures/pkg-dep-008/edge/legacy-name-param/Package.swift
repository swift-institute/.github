// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fixture-legacy-name-param",
    dependencies: [
        .package(name: "Custom", url: "https://github.com/org/other-name.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Fixture",
            dependencies: [
                .product(name: "Thing", package: "Custom"),
            ]
        ),
    ]
)
