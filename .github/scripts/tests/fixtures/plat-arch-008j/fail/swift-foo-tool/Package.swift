// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-foo-tool",
    products: [
        .library(name: "Foo Tool", targets: ["Foo Tool"]),
    ],
    targets: [
        .target(name: "Foo Tool"),
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
