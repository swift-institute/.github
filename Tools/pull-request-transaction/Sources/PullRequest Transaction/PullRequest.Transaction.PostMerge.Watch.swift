extension PullRequest.Transaction.PostMerge {
    /// The raw signal captured by verify-post-merge.yml's dispatch-and-await
    /// step. Every field but `repository` and `expectedHead` may be absent
    /// — that absence is exactly what `classify(_:)` must turn into
    /// `.lost`, never into silence.
    public struct Watch: Codable, Equatable, Sendable {
        public let repository: String
        public let expectedHead: String
        /// The dispatch step's own GitHub-native step result: `success`,
        /// `failure`, `cancelled`, or `skipped`.
        public let stepOutcome: String
        /// The awaited run's own terminal conclusion, set only once the
        /// watch actually reached one.
        public let conclusion: String?
        public let runURL: String?
        /// The specific lost class the dispatch step recorded before an
        /// early exit, when it recorded one; `classify(_:)` infers a
        /// fallback reason from `stepOutcome` when this is absent.
        public let lostReason: String?

        public init(
            repository: String,
            expectedHead: String,
            stepOutcome: String,
            conclusion: String?,
            runURL: String?,
            lostReason: String?
        ) {
            self.repository = repository
            self.expectedHead = expectedHead
            self.stepOutcome = stepOutcome
            self.conclusion = conclusion
            self.runURL = runURL
            self.lostReason = lostReason
        }
    }
}
