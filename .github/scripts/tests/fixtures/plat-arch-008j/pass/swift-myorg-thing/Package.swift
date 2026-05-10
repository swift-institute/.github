// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-myorg-thing",
    products: [
        .library(name: "Myorg Thing", targets: ["Myorg Thing"]),
    ],
    targets: [
        .target(name: "Myorg Thing"),
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
