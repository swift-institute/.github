// swift-tools-version: 6.3.1

import PackageDescription

// Non-platform package — [PLAT-ARCH-006] only applies to L3 platform
// packages (swift-darwin / swift-linux / swift-windows / swift-posix).
let package = Package(
    name: "swift-foo",
    products: [.library(name: "Foo", targets: ["Foo"])],
    targets: [.target(name: "Foo")],
    swiftLanguageModes: [.v6]
)
