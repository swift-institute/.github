// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-extension-good",
    products: [
        .library(name: "Ext Module", targets: ["Ext Module"]),
    ],
    targets: [
        .target(name: "Ext Module"),
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
