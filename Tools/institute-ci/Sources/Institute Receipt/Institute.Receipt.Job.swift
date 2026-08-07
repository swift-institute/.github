extension Institute.Receipt {
    /// One paginated job row. `mandatory` is derived from the plan's
    /// gating set; a mandatory job that skipped, was cancelled, or has an
    /// untyped nil conclusion refuses terminality (§8.13; R35).
    public struct Job: Sendable, Equatable {
        public let id: Int?
        public let name: String
        public let conclusion: Conclusion?
        public let selected: Bool
        public let mandatory: Bool
        /// The runner labels the job actually ran on, as the jobs
        /// collection reported them.
        public let runnerLabels: [String]

        public init(
            id: Int?, name: String, conclusion: Conclusion?,
            selected: Bool, mandatory: Bool,
            runnerLabels: [String] = []
        ) {
            self.id = id
            self.name = name
            self.conclusion = conclusion
            self.selected = selected
            self.mandatory = mandatory
            self.runnerLabels = runnerLabels
        }
    }

    /// A typed measurement loss: the only lawful representation of
    /// missing evidence (UNMEASURED over silence, always with a cause).
    public struct Unmeasured: Sendable, Equatable {
        public let field: String
        public let reason: String

        public init(field: String, reason: String) {
            self.field = field
            self.reason = reason
        }
    }
}

extension Institute.Receipt.Job {
    /// How the job is named in a typed-loss row and in a refusal —
    /// its numeric id, or `?` when the jobs collection carried none.
    ///
    /// The retired corpus interpolated `j.get('id')` directly, so a job
    /// without an id produced the field name `jobs[None].conclusion` and
    /// the row it was meant to pair with was never matched.
    public var identifier: String {
        id.map(String.init) ?? "?"
    }
}
