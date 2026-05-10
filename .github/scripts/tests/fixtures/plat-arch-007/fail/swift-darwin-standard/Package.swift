// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-darwin-standard",
    products: [
        .library(name: "Darwin Kernel Standard", targets: ["Darwin Kernel Standard"]),
    ],
    targets: [
        .target(name: "Darwin Kernel Standard"),
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
