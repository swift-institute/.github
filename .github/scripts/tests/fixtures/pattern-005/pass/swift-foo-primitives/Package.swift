// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-foo-primitives",
    products: [
        .library(name: "Foo Primitives", targets: ["Foo Primitives"]),
    ],
    targets: [
        .target(name: "Foo Primitives"),
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
