// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-iso-9945",
    products: [
        .library(name: "ISO 9945", targets: ["ISO 9945"]),
    ],
    targets: [
        .target(name: "ISO 9945"),
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
