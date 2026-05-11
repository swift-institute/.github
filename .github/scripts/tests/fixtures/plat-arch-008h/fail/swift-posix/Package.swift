// swift-tools-version: 6.3.1

import PackageDescription

// swift-posix is L3-policy. Depending on swift-kernel (L3-unifier) is
// UPWARD composition — VIOLATION of [PLAT-ARCH-008h] matrix cell
// (L3-policy → L3-unifier is forbidden).
let package = Package(
    name: "swift-posix",
    dependencies: [
        .package(path: "../swift-kernel"),
    ],
    products: [.library(name: "POSIX Kernel", targets: ["POSIX"])],
    targets: [
        .target(name: "POSIX", dependencies: [
            .product(name: "Kernel", package: "swift-kernel"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
