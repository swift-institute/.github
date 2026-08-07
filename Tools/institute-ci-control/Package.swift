// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Institute CI Control",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "institute-ci-control",
            targets: ["Institute CI Control Command"]
        ),
        .library(
            name: "GitHub Control",
            targets: ["GitHub Control"]
        ),
        .library(
            name: "Fleet Audit",
            targets: ["Fleet Audit"]
        ),
        .library(
            name: "Fleet Inventory",
            targets: ["Fleet Inventory"]
        ),
        .library(
            name: "Fleet Convergence",
            targets: ["Fleet Convergence"]
        ),
        .library(
            name: "Private Verification",
            targets: ["Private Verification"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-github.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-github-http.git", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-fips-180-4.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "GitHub Control",
            dependencies: [
                .product(name: "GitHub", package: "swift-github"),
                .product(name: "GitHub HTTP", package: "swift-github-http"),
            ]
        ),
        // The cron sweep contract: what a caller may configure, what
        // one package's audit reports, how a sweep accumulates them.
        // Pure — the credentialed edge is the Application's.
        .target(
            name: "Fleet Audit"
        ),
        .target(
            name: "Fleet Inventory"
        ),
        .target(
            name: "Fleet Convergence",
            dependencies: ["Fleet Inventory"]
        ),
        .target(
            name: "Private Verification",
            dependencies: [
                .product(name: "FIPS 180-4", package: "swift-fips-180-4"),
            ]
        ),
        .target(
            name: "Institute CI Control Application",
            dependencies: [
                "GitHub Control", "Fleet Audit", "Fleet Inventory",
                "Fleet Convergence",
                "Private Verification",
            ]
        ),
        .executableTarget(
            name: "Institute CI Control Command",
            dependencies: [
                "Institute CI Control Application", "Fleet Audit", "GitHub Control",
            ]
        ),
        .testTarget(
            name: "Fleet Audit Tests",
            dependencies: ["Fleet Audit"]
        ),
        .testTarget(
            name: "Fleet Convergence Tests",
            dependencies: ["Fleet Convergence"]
        ),
        .testTarget(
            name: "GitHub Control Tests",
            dependencies: ["GitHub Control"]
        ),
        .testTarget(
            name: "Private Verification Tests",
            dependencies: ["Private Verification"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
