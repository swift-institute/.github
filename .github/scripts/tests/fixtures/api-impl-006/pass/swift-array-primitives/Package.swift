// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-array-primitives",
    products: [
        .library(name: "Array Primitives", targets: ["Array Primitives"]),
    ],
    targets: [
        .target(name: "Array Primitives"),
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
