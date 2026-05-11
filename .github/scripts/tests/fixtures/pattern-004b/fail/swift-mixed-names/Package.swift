// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-mixed-names",
    products: [
        .library(name: "Real_Primitives Core", targets: ["Real_Primitives Core"]),
    ],
    targets: [
        // Mixes spaces and underscores — VIOLATION of [PATTERN-004b].
        .target(name: "Real_Primitives Core"),
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
