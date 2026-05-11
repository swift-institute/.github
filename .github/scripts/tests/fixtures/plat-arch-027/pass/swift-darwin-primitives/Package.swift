// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-darwin-primitives",
    products: [.library(name: "Darwin Kernel Primitives", targets: ["Darwin Kernel Primitives"])],
    targets: [
        .target(name: "Darwin Primitives Core"),
        .target(name: "Darwin Kernel Primitives", dependencies: ["Darwin Primitives Core"]),
    ],
    swiftLanguageModes: [.v6]
)
