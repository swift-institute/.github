// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-spec-names",
    products: [
        .library(name: "RFC_4122", targets: ["RFC_4122"]),
    ],
    targets: [
        // Pure spec-namespace form per [API-NAME-003] — underscore is part
        // of the spec identifier. NOT a violation of [PATTERN-004b].
        .target(name: "RFC_4122"),
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
