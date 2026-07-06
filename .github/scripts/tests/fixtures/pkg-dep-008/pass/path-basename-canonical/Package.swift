// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fixture-path-basename",
    dependencies: [
        .package(path: "Vendor/swift-dep"),
    ],
    targets: [
        .target(
            name: "Fixture",
            dependencies: [
                .product(name: "Dep", package: "swift-dep"),
            ]
        ),
    ]
)
