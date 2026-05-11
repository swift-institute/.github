// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-extension-bad",
    products: [
        .library(name: "Bad Module", targets: ["Bad Module"]),
    ],
    targets: [
        .target(name: "Bad Module"),
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
