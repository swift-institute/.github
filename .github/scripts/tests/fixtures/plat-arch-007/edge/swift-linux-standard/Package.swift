// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-linux-standard",
    products: [
        .library(name: "Linux Standard", targets: ["Linux Standard"]),
    ],
    targets: [
        .target(name: "Linux Standard"),
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
