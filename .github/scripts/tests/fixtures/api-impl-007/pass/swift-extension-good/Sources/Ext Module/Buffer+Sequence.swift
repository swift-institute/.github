// `Buffer+Sequence.swift` — extension file with `+` segment marking the
// conformance-extension shape per [API-IMPL-007]. Pure-extension content;
// basename's `+` discriminator satisfies the rule.

public struct Buffer {
    public init() {}
}

// Above declaration is the primary type; the file below is the extension
// addition that justifies the basename. The mechanical "pure extension
// file" check excludes this file (it carries a top-level struct decl),
// so [API-IMPL-007] doesn't fire on this scenario. Kept as a sibling so
// downstream readers see the canonical type/extension pairing.
