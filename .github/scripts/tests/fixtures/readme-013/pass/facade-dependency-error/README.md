# swift-facade

A facade over kernel primitives. It re-exports and forwards; every throwing
surface propagates a dependency's error type, and the package declares none of
its own.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-facade.git", branch: "main")
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Facade", package: "swift-facade")
    ]
)
```

## License

Apache 2.0. See [LICENSE](LICENSE).
