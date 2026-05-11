// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-bad-rule",
    products: [
        .library(name: "Linter Rule Foo", targets: ["Linter Rule Foo"]),
    ],
    targets: [
        .target(name: "Linter Rule Foo"),
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
