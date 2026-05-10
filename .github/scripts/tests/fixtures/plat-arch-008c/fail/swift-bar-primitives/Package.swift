// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-bar-primitives",
    products: [
        .library(name: "Bar Primitives", targets: ["Bar Primitives"]),
    ],
    targets: [
        .target(name: "Bar Primitives"),
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
