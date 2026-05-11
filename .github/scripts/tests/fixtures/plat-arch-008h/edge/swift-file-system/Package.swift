// swift-tools-version: 6.3.1

import PackageDescription

// swift-file-system (L3-domain) depending on L3-unifier `swift-kernel` is
// permitted per [PLAT-ARCH-008h]. (No deps on L3-policy here.)
let package = Package(
    name: "swift-file-system",
    dependencies: [
        .package(path: "../swift-kernel"),
        .package(path: "../swift-paths"),
    ],
    products: [.library(name: "File System", targets: ["FS"])],
    targets: [
        .target(name: "FS", dependencies: [
            .product(name: "Kernel", package: "swift-kernel"),
            .product(name: "Paths", package: "swift-paths"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
