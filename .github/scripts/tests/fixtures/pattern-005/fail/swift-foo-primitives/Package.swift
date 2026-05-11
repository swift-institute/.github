// swift-tools-version: 6.0

import PackageDescription

// VIOLATION of [PATTERN-005]: swift-tools-version < 6.3 AND missing
// `swiftLanguageModes: [.v6]`.
let package = Package(
    name: "swift-foo-primitives",
    products: [
        .library(name: "Foo Primitives", targets: ["Foo Primitives"]),
    ],
    targets: [
        .target(name: "Foo Primitives"),
    ]
)

for target in package.targets where target.type != .system {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
