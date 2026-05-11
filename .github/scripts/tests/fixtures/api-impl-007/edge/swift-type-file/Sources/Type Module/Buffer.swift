// `Buffer.swift` — type-declaring file containing the type declaration AND
// extensions on the same type. Not a "pure-extension file" because of the
// top-level `struct` declaration; [API-IMPL-007] does NOT fire. The
// dotted-naming rule [API-IMPL-006] is also satisfied (single-word).

public struct Buffer {
    public init() {}
}

extension Buffer {
    public var isEmpty: Bool { true }
}
