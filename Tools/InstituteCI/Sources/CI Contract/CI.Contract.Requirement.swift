extension CI.Contract {
    /// What one aggregate participant is required to have done: a leg the
    /// plan selected as gating must succeed; every other gating job must
    /// have skipped. The required check context this feeds is exactly
    /// `ci / matrix / ci-ok` and never migrates (FT1; R-08).
    public struct Requirement: Sendable, Equatable {
        public enum Expectation: String, Sendable, Equatable {
            case success
            case skipped
        }

        public static let checkContext = "ci / matrix / ci-ok"

        public let job: String
        public let expectation: Expectation

        public init(job: String, expectation: Expectation) {
            self.job = job
            self.expectation = expectation
        }

        /// The requirement table for one aggregate: every participating
        /// job (ci-ok's needs minus plan) against the plan's gating set.
        public static func table(
            participants: [String], gating: [Leg]
        ) -> [Requirement] {
            let gatingIds = Set(gating.map(\.id))
            return participants.filter { $0 != "plan" }.map { job in
                Requirement(
                    job: job,
                    expectation: gatingIds.contains(job) ? .success : .skipped)
            }
        }
    }
}
