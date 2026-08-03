// [swift-institute/.github#218] VIOLATION: genuine arithmetic (division) on
// an `Int(bitPattern:)` call site, same line, no comment involved.
// `no_int_bitpattern_arithmetic` MUST still fire — the #218 fix narrows the
// regex's comment-opener false positive, it does not touch true division.

func half(of raw: UInt) -> Int {
    Int(bitPattern: raw) / 2
}
