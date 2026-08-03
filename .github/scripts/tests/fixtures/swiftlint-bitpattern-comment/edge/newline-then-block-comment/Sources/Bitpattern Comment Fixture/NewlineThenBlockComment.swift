// [swift-institute/.github#218] EXEMPT: block-comment counterpart to the
// witness reproduction — the `Int(bitPattern:)` call ends the statement, a
// blank line follows, and the next non-whitespace character is the `/` of
// a `/*` block comment two lines below. No arithmetic is present.
// `no_int_bitpattern_arithmetic` must NOT fire.

func count(of shape: [Int]) -> Int {
    let total = Int(bitPattern: shape.count)

    /* next statement builds the result */
    return total
}
