// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-type-file",
    products: [
        .library(name: "Type Module", targets: ["Type Module"]),
    ],
    targets: [
        .target(name: "Type Module"),
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
