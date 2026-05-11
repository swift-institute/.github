// `Buffer.swift` — pure-extension file (top-level decls are ALL `extension`)
// whose basename lacks the `+` segment AND lacks a ` where ` discriminator.
// VIOLATION of [API-IMPL-007]. Should be `Buffer+Sequence.swift`.

extension Buffer: Sequence {
    public func makeIterator() -> EmptyCollection<Int>.Iterator {
        EmptyCollection<Int>().makeIterator()
    }
}

extension Buffer: Equatable {}
