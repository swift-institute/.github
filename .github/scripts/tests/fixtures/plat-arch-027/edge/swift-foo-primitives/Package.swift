// swift-tools-version: 6.3.1

import PackageDescription

// Non-platform-primitives package — [PLAT-ARCH-027] is scoped to swift-
// darwin-primitives / swift-linux-primitives / swift-windows-primitives.
let package = Package(
    name: "swift-foo-primitives",
    products: [.library(name: "Foo Primitives", targets: ["Foo Primitives"])],
    targets: [.target(name: "Foo Primitives")],
    swiftLanguageModes: [.v6]
)
