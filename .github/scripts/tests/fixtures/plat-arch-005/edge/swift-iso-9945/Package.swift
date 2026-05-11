// swift-tools-version: 6.3.1

import PackageDescription

// L2-canonical: ISO_9945 may declare a concrete Descriptor type.
// [PLAT-ARCH-005] only constrains L1 (swift-kernel-primitives).
let package = Package(
    name: "swift-iso-9945",
    products: [.library(name: "ISO 9945 Core", targets: ["ISO 9945 Core"])],
    targets: [.target(name: "ISO 9945 Core")],
    swiftLanguageModes: [.v6]
)
