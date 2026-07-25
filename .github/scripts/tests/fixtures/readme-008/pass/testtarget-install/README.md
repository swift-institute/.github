# swift-example-testing

A test-support package whose product is wired into a consumer's test target.

## Installation

Add the dependency to your `Package.swift` (pre-tag — pin to `main`):

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-example-testing.git", branch: "main")
]
```

Add the product to your test target:

```swift
.testTarget(
    name: "YourTests",
    dependencies: [
        .product(name: "ExampleTesting", package: "swift-example-testing")
    ]
)
```

## License

Apache 2.0. See [LICENSE](LICENSE).
