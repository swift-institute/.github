# swift-widget

A widget package that owns a three-arm error enum, throws it, AND documents the
error tree — so README-013 is satisfied and must not fire.

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

## Error Handling

```
Widget.Error
├── .notFound   // no matching record
├── .invalid    // malformed input
└── .timedOut   // deadline exceeded
```

```swift
do {
    try widget.load()
} catch .notFound {
    // handle
} catch .invalid {
    // handle
} catch .timedOut {
    // handle
}
```

## License

Apache 2.0. See [LICENSE](LICENSE).
