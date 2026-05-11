// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-kernel",
    products: [.library(name: "Kernel", targets: ["Kernel"])],
    targets: [.target(name: "Kernel")],
    swiftLanguageModes: [.v6]
)
