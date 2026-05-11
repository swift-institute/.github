// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-foo",
    dependencies: [
        .package(name: "swift-darwin-standard", path: "../swift-darwin-standard"),
    ],
    products: [
        .library(name: "Foo", targets: ["Foo"]),
    ],
    targets: [
        .target(name: "Foo", dependencies: [
            .product(
                name: "Darwin Kernel Standard",
                package: "swift-darwin-standard",
                condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS])
            ),
        ]),
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
