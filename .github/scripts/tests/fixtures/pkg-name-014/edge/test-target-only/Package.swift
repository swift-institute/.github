// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "h",
    dependencies: [.package(path: "Vendor/swift-base")],
    targets: [.target(name: "Own Thing"), .testTarget(name: "Rule Memory")]
)
