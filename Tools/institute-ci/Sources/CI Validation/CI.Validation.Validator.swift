import CI_Contract

extension CI.Validation {
    /// One rule implementation.
    ///
    /// The whole contract, and nothing more:
    ///
    /// - `rules` — the identifiers this validator is authoritative for.
    ///   Several validators cover more than one (`CI-040`/`CI-042`), and
    ///   the fixture corpus indexes by rule, not by validator.
    /// - `findings(in:)` — a pure question. It returns; it does not
    ///   print, exit, or read process state. That is what makes the
    ///   differential gate, the fixture harness, and in-process tests all
    ///   possible against the same code.
    /// - `throws(EnvironmentDefect)` — the only failure a validator may
    ///   raise. A rule violation is a return value; an unanswerable
    ///   question is the throw. Typed throws makes the two
    ///   non-interchangeable at compile time rather than by convention.
    ///
    /// Findings are returned in the order the validator discovered them.
    /// Callers that compare implementations sort first; see
    /// `Finding.tsv`.
    /// A validator is a *value*, not a type the registry reflects over.
    /// It is stateless and `Sendable`, so one instance answers for the
    /// whole process and the registry is a plain array.
    public protocol Validator: Sendable {
        /// The rule identifiers this validator answers for.
        var rules: [Rule] { get }

        /// The retired script this validator replaces, if any — the
        /// path under `swift-institute/.github`, e.g.
        /// `.github/scripts/validate-continue-on-error.py`.
        ///
        /// Recorded on the validator so the differential gate can find
        /// its counterpart without a second lookup table, and so the
        /// record of what has been ported is the code itself rather than
        /// a document that drifts. `nil` once the counterpart is deleted.
        var retiredScript: String? { get }

        /// Every violation this validator finds in the subject.
        func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding]
    }
}

extension CI.Validation.Validator {
    public var retiredScript: String? { nil }
}
