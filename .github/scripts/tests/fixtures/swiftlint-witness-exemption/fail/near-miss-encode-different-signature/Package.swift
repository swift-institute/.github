// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-witness-exemption-fixture",
    products: [
        .library(name: "Witness Exemption Fixture", targets: ["Witness Exemption Fixture"]),
    ],
    targets: [
        .target(name: "Witness Exemption Fixture"),
    ],
    swiftLanguageModes: [.v6]
)
