import Fleet_Inventory

extension Fleet.Convergence {
    /// Resume-not-restart: rehydrates an interrupted apply from its
    /// persisted journal and reports exactly what remains. Shuffled or
    /// drifted journals refuse (K-22).
    public enum Resume {
        public struct State: Sendable, Equatable {
            public let apply: Apply
            public let remaining: [Plan.Step]

            public init(apply: Apply, remaining: [Plan.Step]) {
                self.apply = apply
                self.remaining = remaining
            }
        }

        public static func from(
            plan: Plan, journal: [Apply.Entry]
        ) throws(Apply.Error) -> State {
            let apply = try Apply(plan: plan, journal: journal)
            let remaining = zip(plan.steps, journal)
                .filter { _, entry in
                    entry.status != .readBack && entry.status != .rolledBack
                }
                .map(\.0)
            return State(apply: apply, remaining: remaining)
        }
    }

    /// One post-mutation readback row: the terminal re-read of exact
    /// post-state, compared against the intended payload digest. A write
    /// without a matching readback is not terminal.
    public struct Readback: Sendable, Equatable {
        public let repository: String
        public let coordinate: String
        public let expectedDigest: String
        public let observedDigest: String

        public var converged: Bool { expectedDigest == observedDigest }

        public init(
            repository: String, coordinate: String,
            expectedDigest: String, observedDigest: String
        ) {
            self.repository = repository
            self.coordinate = coordinate
            self.expectedDigest = expectedDigest
            self.observedDigest = observedDigest
        }
    }
}
