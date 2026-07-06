// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "tooling",
    targets: [
        .target(name: "Tooling"),
        .testTarget(name: "Tooling Tests", dependencies: ["Tooling"]),
    ]
)
