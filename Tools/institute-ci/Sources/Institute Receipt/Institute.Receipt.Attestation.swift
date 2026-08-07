extension Institute.Receipt {
    /// A complete version-1 effective runtime receipt: the measured
    /// facts, which half of the two-phase attestation they were measured
    /// in, the binding digest that makes a terminal record terminal, and
    /// the verdict those three support.
    ///
    /// The four are one value because they are only meaningful together.
    /// A verdict without a stage cannot be read (`MET` in-run is not a
    /// claim anyone may make); a terminal stage without a base digest is
    /// an unbound assertion; and the facts alone say nothing about what
    /// was concluded from them. `Canonical` is the codec for exactly
    /// this value, and it is what the digest is taken over.
    public struct Attestation: Sendable, Equatable {
        public let base: Preterminal
        public let stage: Stage
        /// SHA-256 of the preterminal record this record augments, and
        /// `nil` for the preterminal record itself.
        public let baseReceiptDigest: String?
        public let verdict: Verdict

        public init(
            base: Preterminal,
            stage: Stage,
            baseReceiptDigest: String?,
            verdict: Verdict
        ) {
            self.base = base
            self.stage = stage
            self.baseReceiptDigest = baseReceiptDigest
            self.verdict = verdict
        }
    }
}

extension Institute.Receipt.Attestation {
    /// The readiness view: the same facts, asked whether they are
    /// terminal. Keeps `Institute.Receipt.Terminal.validate()` the one
    /// owner of the §13.3 refusal classes rather than growing a second
    /// predicate here.
    public var terminal: Institute.Receipt.Terminal {
        .init(base: base, baseReceiptDigest: baseReceiptDigest)
    }
}
