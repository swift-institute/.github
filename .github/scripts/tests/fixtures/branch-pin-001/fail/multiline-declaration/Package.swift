// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        .package(
            url: "https://github.com/swift-foundations/swift-example.git",
            // interleaved comment inside the declaration window
            branch: "main"
        ),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
