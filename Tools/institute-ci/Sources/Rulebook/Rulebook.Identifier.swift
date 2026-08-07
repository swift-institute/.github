extension Rulebook {
    /// A rulebook identifier — `API-NAME-001`, `PLAT-ARCH-008g`,
    /// `IMPL-INTENT`.
    ///
    /// Two grammars, both sanctioned:
    ///
    /// - **numeric** — `PREFIX(-SEGMENT)*-NNN` with an optional single
    ///   lower-case suffix. Every segment after the first begins with a
    ///   letter, which is what makes `[PATTERN-012-062]` read as the
    ///   range `012`–`062` rather than as one identifier.
    /// - **word** — two or more all-capital segments and no digits, the
    ///   form the axioms take (`IMPL-INTENT`, `MOD-OWNER`).
    ///
    /// A bare `String` would have worked; a type is here because the
    /// identifier is simultaneously a citation token, a definition site
    /// key, a baseline line, and an allowlist key, and the corpus review
    /// found those four disagreeing.
    public struct Identifier: Sendable, Hashable, Comparable, RawRepresentable,
        ExpressibleByStringLiteral, CustomStringConvertible
    {
        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public var description: String { rawValue }
    }
}

extension Rulebook.Identifier {
    /// A numeric identifier split at its **last** `-<digits>` group.
    ///
    /// `API-NAME-001` → (`API-NAME`, 1, ``); `HANDOFF-024a` →
    /// (`HANDOFF`, 24, `a`). `nil` for a word-form identifier, which has
    /// no number to compare.
    public var parts: (family: String, number: Int, suffix: String)? {
        var characters = Array(rawValue)
        var suffix = ""
        if let last = characters.last, last.isLowercase, last.isLetter {
            suffix = String(last)
            characters.removeLast()
        }
        var digits = ""
        while let last = characters.last, last.isNumber {
            digits.insert(last, at: digits.startIndex)
            characters.removeLast()
        }
        guard !digits.isEmpty, characters.last == "-", let number = Int(digits) else { return nil }
        characters.removeLast()
        guard !characters.isEmpty else { return nil }
        return (String(characters), number, suffix)
    }

    /// Ordering by family, then number, then suffix — so `X-9` precedes
    /// `X-10`, which lexicographic ordering of the raw text does not.
    /// A word-form identifier sorts by its text, ahead of any numbered
    /// sibling.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let left = lhs.parts.map { ($0.family, $0.number, $0.suffix) } ?? (lhs.rawValue, -1, "")
        let right = rhs.parts.map { ($0.family, $0.number, $0.suffix) } ?? (rhs.rawValue, -1, "")
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1 < right.1 }
        return left.2 < right.2
    }

    /// Whether the text is a well-formed numeric identifier.
    public static func isNumeric(_ text: String) -> Bool {
        let segments = text.split(separator: "-", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        var last = segments[segments.count - 1]
        if let final = last.last, final.isLowercase, final.isLetter { last = last.dropLast() }
        guard (1...3).contains(last.count), last.allSatisfy(\.isNumber) else { return false }
        for segment in segments.dropLast() {
            guard let first = segment.first, first.isUppercase, first.isLetter else { return false }
            guard segment.allSatisfy({ ($0.isUppercase && $0.isLetter) || $0.isNumber })
            else { return false }
        }
        return true
    }

    /// Whether the text is a well-formed word-form identifier: two or
    /// more all-capital segments, no digits.
    public static func isWord(_ text: String) -> Bool {
        let segments = text.split(separator: "-", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            segment.count >= 2 && segment.allSatisfy { $0.isUppercase && $0.isLetter }
        }
    }

    /// Whether the text is a well-formed identifier **prefix** — the
    /// part a wildcard names, `[MEM-COPY-*]` → `MEM-COPY`.
    public static func isPrefix(_ text: String) -> Bool {
        let segments = text.split(separator: "-", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { segment in
            guard let first = segment.first, first.isUppercase, first.isLetter else { return false }
            return segment.allSatisfy { ($0.isUppercase && $0.isLetter) || $0.isNumber }
        }
    }

    /// The members of `start`…`end`.
    ///
    /// A registry header stating a range claims each member explicitly,
    /// so the range is expanded. Expansion is refused — and the two
    /// endpoints returned alone — when arithmetic would be meaningless:
    /// different families, a letter suffix on either end, a descending
    /// pair, or a span wider than 200. Refusing is deliberate: a sparse
    /// range like `PATTERN-012–062` is corpus-legal, and inventing its
    /// missing members would turn one citation into fifty phantom
    /// definitions.
    ///
    /// Zero-padding follows the *start* identifier's width, which is what
    /// makes `X-010`…`X-012` expand to `X-010`, `X-011`, `X-012` and not
    /// to `X-10`.
    public static func range(from start: Self, to end: Self) -> Set<Self> {
        guard let first = start.parts, let last = end.parts,
            first.family == last.family, first.suffix.isEmpty, last.suffix.isEmpty,
            last.number >= first.number, last.number - first.number <= 200
        else { return [start, end] }
        let width = start.rawValue.count - first.family.count - 1
        return Set(
            (first.number...last.number).map { number in
                Self("\(first.family)-\(String(number).paddedWithZeros(to: width))")
            })
    }
}

extension String {
    /// Left-padded with `0` to `width`; unchanged when already wider.
    fileprivate func paddedWithZeros(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
