// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-bitpattern-comment-fixture",
    products: [
        .library(name: "Bitpattern Comment Fixture", targets: ["Bitpattern Comment Fixture"]),
    ],
    targets: [
        .target(name: "Bitpattern Comment Fixture"),
    ],
    swiftLanguageModes: [.v6]
)
