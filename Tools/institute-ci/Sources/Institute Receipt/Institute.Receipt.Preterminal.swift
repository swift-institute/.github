extension Institute.Receipt {
    /// The in-run (preterminal) effective runtime receipt: what the
    /// aggregate can measure about its own run, with every loss typed.
    public struct Preterminal: Sendable, Equatable {
        public let run: Run
        public let subjectRepository: String
        public let subjectSha: String
        /// The subject repository's visibility at capture time.
        public let subjectVisibility: String
        public let referencedWorkflows: [ReferencedWorkflow]
        public let jobs: [Job]
        /// Reported total from the paginated jobs collection; must equal
        /// `jobs.count` or pagination is incomplete.
        public let jobsTotalCount: Int?
        public let unmeasured: [Unmeasured]

        public init(
            run: Run, subjectRepository: String, subjectSha: String,
            subjectVisibility: String = "",
            referencedWorkflows: [ReferencedWorkflow], jobs: [Job],
            jobsTotalCount: Int?, unmeasured: [Unmeasured]
        ) {
            self.run = run
            self.subjectRepository = subjectRepository
            self.subjectSha = subjectSha
            self.subjectVisibility = subjectVisibility
            self.referencedWorkflows = referencedWorkflows
            self.jobs = jobs
            self.jobsTotalCount = jobsTotalCount
            self.unmeasured = unmeasured
        }
    }
}
