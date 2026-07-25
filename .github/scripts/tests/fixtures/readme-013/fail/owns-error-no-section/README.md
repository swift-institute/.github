# swift-widget

A widget package that owns a three-arm error enum and throws it, but omits the
error-tree documentation the error shape requires.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-widget.git", branch: "main")
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Widget", package: "swift-widget")
    ]
)
```

## License

Apache 2.0. See [LICENSE](LICENSE).
