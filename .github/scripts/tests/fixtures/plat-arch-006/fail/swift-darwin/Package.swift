// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-darwin",
    products: [.library(name: "Darwin Kernel", targets: ["Darwin Kernel"])],
    targets: [.target(name: "Darwin Kernel")],
    swiftLanguageModes: [.v6]
)
