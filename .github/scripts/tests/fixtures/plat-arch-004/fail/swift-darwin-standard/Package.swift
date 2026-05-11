// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-darwin-standard",
    products: [.library(name: "Darwin Standard Core", targets: ["Darwin Standard Core"])],
    targets: [.target(name: "Darwin Standard Core")],
    swiftLanguageModes: [.v6]
)
