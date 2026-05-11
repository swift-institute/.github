// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-foo",
    products: [.library(name: "Foo", targets: ["Foo"])],
    targets: [.target(name: "Foo")],
    swiftLanguageModes: [.v6]
)
