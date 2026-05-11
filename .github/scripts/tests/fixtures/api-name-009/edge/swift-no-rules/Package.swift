// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-no-rules",
    products: [
        .library(name: "Mod", targets: ["Mod"]),
    ],
    targets: [
        .target(name: "Mod"),
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
