// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-kernel-primitives",
    products: [.library(name: "Kernel Primitives", targets: ["Kernel Primitives"])],
    targets: [.target(name: "Kernel Primitives")],
    swiftLanguageModes: [.v6]
)
