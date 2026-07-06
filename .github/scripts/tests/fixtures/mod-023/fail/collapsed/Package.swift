// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport
let package = Package(
    name: "f",
    targets: [
        .macro(name: "Fixture Macros", dependencies: []),
        .target(name: "M"),
    ]
)
