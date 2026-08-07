// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "pr-transaction",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PullRequest Transaction", targets: ["PullRequest Transaction"]),
        .executable(name: "pr-transaction", targets: ["PullRequest Transaction CLI"]),
    ],
    targets: [
        .target(name: "PullRequest Transaction"),
        .executableTarget(name: "PullRequest Transaction CLI", dependencies: ["PullRequest Transaction"]),
        .testTarget(
            name: "PullRequest Transaction Tests",
            dependencies: ["PullRequest Transaction"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
