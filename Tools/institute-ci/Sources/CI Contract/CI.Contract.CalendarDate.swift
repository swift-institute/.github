extension CI.Contract {
    /// Whether `text` is a `YYYY-MM-DD` calendar date.
    ///
    /// Both typed CI exceptions bound themselves with a recheck date and
    /// compare dates lexicographically, which is only sound for this exact
    /// zero-padded shape. One owner of the shape keeps the two exceptions
    /// from drifting into two different notions of "a date".
    static func isCalendarDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
