extension Institute.Receipt {
    /// A run's or a job's terminal conclusion, as GitHub spells it.
    ///
    /// A typed identifier rather than a bare `String` because the retired
    /// corpus compared this value against string literals in four
    /// separate places — `!= "success"`, `in (None, "skipped")`,
    /// `== "startup_failure"`, `in ("skipped", "cancelled")` — and a
    /// typo in any of them reads as "clean". The raw spelling is
    /// preserved verbatim so an unrecognised conclusion survives a
    /// receipt round trip byte for byte rather than being folded into an
    /// `unknown` case.
    ///
    /// The names mirror the REST `conclusion` vocabulary; they are
    /// spec-mirroring identifiers, not invented ones.
    public struct Conclusion: Sendable, Hashable, RawRepresentable,
        ExpressibleByStringLiteral, CustomStringConvertible
    {
        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
    }
}

extension Institute.Receipt.Conclusion {
    public var description: String { rawValue }

    public static let success: Self = "success"
    public static let failure: Self = "failure"
    public static let cancelled: Self = "cancelled"
    public static let skipped: Self = "skipped"
    public static let neutral: Self = "neutral"
    public static let stale: Self = "stale"
    public static let timedOut: Self = "timed_out"
    public static let actionRequired: Self = "action_required"

    /// The run never started: bad YAML, a missing reusable, a
    /// `workflow_call` permissions or chain mismatch. No job runs, so
    /// every per-job gate is blind to it — which is why the weekly
    /// probe exists.
    public static let startupFailure: Self = "startup_failure"

}
