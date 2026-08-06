extension Institute.Receipt {
    /// The run identity a receipt attests — always the exact run/attempt
    /// pair, correlated at run level, never inferred from mutable state.
    public struct Run: Sendable, Equatable {
        public let id: Int
        public let attempt: Int
        public let headSha: String
        public let event: String
        /// nil until the run completes; a nil conclusion on a record that
        /// requires completion is a refusal unless typed unmeasured.
        public let conclusion: String?

        public init(
            id: Int, attempt: Int, headSha: String, event: String,
            conclusion: String?
        ) {
            self.id = id
            self.attempt = attempt
            self.headSha = headSha
            self.event = event
            self.conclusion = conclusion
        }
    }

    /// One hop of the reusable-workflow chain: the written `@main` source
    /// ref plus GitHub's same-run resolved SHA. An empty chain is
    /// UNMEASURED and refuses terminality (P20); it is never replaced by
    /// a read of current main.
    public struct ReferencedWorkflow: Sendable, Equatable {
        public let path: String
        public let ref: String
        public let sha: String

        public init(path: String, ref: String, sha: String) {
            self.path = path
            self.ref = ref
            self.sha = sha
        }
    }
}
