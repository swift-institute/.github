// swift-tools-version:6.0
import PackageDescription

// Fixture: non-umbrella module MISSING its DocC catalog → one [DOC-020].
let package = Package(
    name: "Widget",
    targets: [
        .target(name: "Widget"),
    ]
)
