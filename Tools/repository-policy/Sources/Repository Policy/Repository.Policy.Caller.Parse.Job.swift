extension Repository.Policy.Caller.Parse {
    /// One job under `jobs:`, with its body lines.
    struct Job {
        let name: String
        let lines: [String]

        /// The body with comments and blank lines removed and trailing
        /// comments stripped — what two renderings are compared on.
        var significantLines: [String] {
            lines.compactMap(Repository.Policy.Caller.Parse.significant)
        }

        func declares(_ key: String) -> Bool {
            significantLines.contains { $0.trimmed.hasPrefix(key) }
        }

        /// The job's `uses:` target, or `nil`.
        var uses: String? {
            for line in significantLines where line.trimmed.hasPrefix("uses:") {
                return String(line.trimmed.dropFirst("uses:".count)).trimmed
            }
            return nil
        }
    }

    /// The shape a caller is in.
    ///
    /// The callee discriminates the terminal form — only `Render.direct`
    /// calls the universal — and a separate `docs:` job discriminates the
    /// legacy one, which is the only difference the *job set* carries.
}

extension String {
    /// Leading and trailing spaces and tabs removed.
    ///
    /// `fileprivate` deliberately: an internal helper on a stdlib type is
    /// the shape two peers adding files to one target collide on.
    fileprivate var trimmed: String {
        var value = Substring(self)
        while let first = value.first, first == " " || first == "\t" { value = value.dropFirst() }
        while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
        return String(value)
    }
}
