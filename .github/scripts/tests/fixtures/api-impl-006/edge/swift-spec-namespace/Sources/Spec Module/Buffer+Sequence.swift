// `Buffer+Sequence.swift` — `+`-suffix extension form per [API-IMPL-007].
// Exempt from the [API-IMPL-006] compound-without-dots check; the `+`
// marker signals the conformance-extension shape.

extension Buffer: Sequence {}

// Stand-in declaration so this file parses.
public struct Buffer {}
