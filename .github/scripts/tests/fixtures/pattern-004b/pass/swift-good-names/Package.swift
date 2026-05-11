// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-good-names",
    products: [
        .library(name: "Real Primitives", targets: ["Real Primitives"]),
    ],
    targets: [
        .target(name: "Real Primitives"),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where target.type != .system {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
