// swift-tools-version: 6.3.1

import PackageDescription

// Non-platform package — [PLAT-ARCH-004] only applies to swift-darwin-
// standard / linux-standard / windows-32 / iso-9945. Anything else is exempt.
let package = Package(
    name: "swift-foo-primitives",
    products: [.library(name: "Foo Primitives", targets: ["Foo Primitives"])],
    targets: [.target(name: "Foo Primitives")],
    swiftLanguageModes: [.v6]
)
