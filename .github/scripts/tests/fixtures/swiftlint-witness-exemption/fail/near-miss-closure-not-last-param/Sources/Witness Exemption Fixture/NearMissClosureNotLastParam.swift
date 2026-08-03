// [swift-institute/.github#260] VIOLATION: the closure parameter is NOT
// the last parameter before the function's own `throws` — this is not the
// closure-passthrough shape #260 exempts (that exemption's second
// lookbehind requires the closure parameter to be immediately, modulo
// whitespace, adjacent to the parameter list's closing paren). The
// function's own `throws` MUST still be flagged; only the closure
// parameter's own declared `throws` is exempt.

func doThing<T>(
    _ operation: (Int) async throws -> T,
    extra: Int
) throws -> T {
    if extra < 0 { throw MyError.bad }
    return try operation(extra)
}

enum MyError: Error {
    case bad
}
