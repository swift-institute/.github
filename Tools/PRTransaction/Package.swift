// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "pr-transaction",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PR Transaction", targets: ["PR Transaction"]),
        .executable(name: "pr-transaction", targets: ["PR Transaction CLI"]),
    ],
    targets: [
        .target(name: "PR Transaction"),
        .executableTarget(name: "PR Transaction CLI", dependencies: ["PR Transaction"]),
        .testTarget(name: "PR Transaction Tests", dependencies: ["PR Transaction"]),
    ],
    swiftLanguageModes: [.v6]
)
