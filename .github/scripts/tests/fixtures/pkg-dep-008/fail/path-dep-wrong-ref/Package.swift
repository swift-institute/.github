// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fixture-path-dep-wrong-ref",
    dependencies: [
        .package(path: "Vendor/swift-local"),
    ],
    targets: [
        .target(
            name: "Fixture",
            dependencies: [
                .product(name: "Local", package: "swift-other"),
            ]
        ),
    ]
)
