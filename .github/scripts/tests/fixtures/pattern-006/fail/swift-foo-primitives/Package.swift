// swift-tools-version: 6.3.1

import PackageDescription

// VIOLATION of [PATTERN-006]: missing the three required upcoming features.
let package = Package(
    name: "swift-foo-primitives",
    products: [
        .library(name: "Foo Primitives", targets: ["Foo Primitives"]),
    ],
    targets: [
        .target(name: "Foo Primitives"),
    ],
    swiftLanguageModes: [.v6]
)
