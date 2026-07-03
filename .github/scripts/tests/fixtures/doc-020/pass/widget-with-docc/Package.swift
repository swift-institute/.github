// swift-tools-version:6.0
import PackageDescription

// Fixture: non-umbrella module WITH a conforming DocC catalog → no [DOC-020].
let package = Package(
    name: "Widget",
    targets: [
        .target(name: "Widget"),
    ]
)
