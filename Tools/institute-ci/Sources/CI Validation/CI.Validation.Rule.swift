import CI_Contract

extension CI.Validation {
    /// A rule identifier — `CI-105`, `GH-IGNORE-001`, `skill-frontmatter`.
    ///
    /// A typed identifier rather than a bare `String` because it is the
    /// join key across four separate surfaces: the TSV finding's second
    /// column, the fixture-corpus directory name, `validators-manifest.yaml`,
    /// and the aggregation regex in `validate-base.yml`. Those four
    /// spellings drifted apart repeatedly while the identifier was a
    /// string; the manifest exists because of it.
    public struct Rule: Sendable, Hashable, Comparable, RawRepresentable,
        ExpressibleByStringLiteral, CustomStringConvertible
    {
        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public var description: String { rawValue }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}
