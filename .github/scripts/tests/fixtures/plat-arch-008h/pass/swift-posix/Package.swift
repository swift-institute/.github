// swift-tools-version: 6.3.1

import PackageDescription

// swift-posix (L3-policy) depending on swift-iso-9945 (L2 spec) is
// downward composition — permitted per [PLAT-ARCH-008h].
let package = Package(
    name: "swift-posix",
    dependencies: [
        .package(path: "../swift-iso-9945"),
    ],
    products: [.library(name: "POSIX Kernel", targets: ["POSIX"])],
    targets: [
        .target(name: "POSIX", dependencies: [
            .product(name: "ISO 9945 Core", package: "swift-iso-9945"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
