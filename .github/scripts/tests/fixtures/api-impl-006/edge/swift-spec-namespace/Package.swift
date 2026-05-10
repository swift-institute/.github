// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-spec-namespace",
    products: [
        .library(name: "Spec Module", targets: ["Spec Module"]),
    ],
    targets: [
        .target(name: "Spec Module"),
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
