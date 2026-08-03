// [swift-institute/.github#218] VIOLATION: general positive control —
// addition on an `Int(bitPattern:)` call site was flagged before #218 and
// must remain flagged after it. Guards against a regex amendment that
// over-corrects and stops matching the ordinary case.

func offset(_ raw: UInt, by delta: Int) -> Int {
    Int(bitPattern: raw) + delta
}
