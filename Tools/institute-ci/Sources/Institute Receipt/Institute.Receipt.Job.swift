extension Institute.Receipt {
    /// One paginated job row. `mandatory` is derived from the plan's
    /// gating set; a mandatory job that skipped, was cancelled, or has an
    /// untyped nil conclusion refuses terminality (§8.13; R35).
    public struct Job: Sendable, Equatable {
        public let id: Int
        public let name: String
        public let conclusion: String?
        public let selected: Bool
        public let mandatory: Bool

        public init(
            id: Int, name: String, conclusion: String?,
            selected: Bool, mandatory: Bool
        ) {
            self.id = id
            self.name = name
            self.conclusion = conclusion
            self.selected = selected
            self.mandatory = mandatory
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
