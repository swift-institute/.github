// [swift-institute/.github#218] EXEMPT: a same-line trailing `//` comment
// after an `Int(bitPattern:)` call site, with intra-line whitespace before
// the comment opener. No arithmetic is present.
// `no_int_bitpattern_arithmetic` must NOT fire.

func count(of shape: [Int]) -> Int {
    let total = Int(bitPattern: shape.count)  // trailing note, not division

    return total
}
