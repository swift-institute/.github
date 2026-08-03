// [swift-institute/.github#218] VIOLATION: genuine arithmetic (addition)
// wrapped onto the following line, no comment involved anywhere in the
// span. #218's fix narrows the `/` alternative to exclude a comment
// opener; it must NOT also stop matching across an ordinary line wrap.
// `no_int_bitpattern_arithmetic` MUST still fire.

func offset(_ raw: UInt, by delta: Int) -> Int {
    Int(bitPattern: raw)
        + delta
}
