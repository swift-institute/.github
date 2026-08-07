extension Institute.Receipt {
    /// The run identity a receipt attests — always the exact run/attempt
    /// pair, correlated at run level, never inferred from mutable state.
    ///
    /// Every field but `headBranch` and `conclusion` is optional because
    /// the capture reads them out of a run object that may not carry
    /// them; an absent field is paired with a typed `Unmeasured` row
    /// rather than silently defaulted. `headBranch` is legitimately null
    /// on a tag or a detached ref, and `conclusion` is null for the
    /// whole preterminal stage, so neither absence is a loss.
    public struct Run: Sendable, Equatable {
        public let id: Int?
        public let attempt: Int?
        public let headSha: String?
        public let event: String?
        /// nil until the run completes; a nil conclusion on a record that
        /// requires completion is a refusal unless typed unmeasured.
        public let conclusion: Conclusion?
        /// `owner/name` of the repository the run belongs to.
        public let repository: String?
        /// The workflow file the run was started from.
        public let workflowPath: String?
        public let actor: String?
        public let headRepository: String?
        public let headBranch: String?

        public init(
            id: Int?, attempt: Int?, headSha: String?, event: String?,
            conclusion: Conclusion?,
            repository: String? = nil,
            workflowPath: String? = nil,
            actor: String? = nil,
            headRepository: String? = nil,
            headBranch: String? = nil
        ) {
            self.id = id
            self.attempt = attempt
            self.headSha = headSha
            self.event = event
            self.conclusion = conclusion
            self.repository = repository
            self.workflowPath = workflowPath
            self.actor = actor
            self.headRepository = headRepository
            self.headBranch = headBranch
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
