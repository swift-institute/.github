import Fleet_Inventory

extension Fleet.Convergence {
    /// The durable application of one plan: a journal of per-step
    /// transitions (DurableTransaction shape). Every write is preceded by
    /// its journal row; a crash resumes from the journal, never restarts.
    public struct Apply: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case pending
            case preimageVerified = "preimage-verified"
            case written
            case readBack = "read-back"
            case failed
            case rolledBack = "rolled-back"
        }

        public struct Entry: Sendable, Equatable {
            public let repository: String
            public let coordinate: String
            public var status: Status
            /// Post-write readback digest; a written step without a
            /// readback digest is not terminal.
            public var readbackDigest: String?
            public var note: String

            public init(
                repository: String, coordinate: String,
                status: Status = .pending, readbackDigest: String? = nil,
                note: String = ""
            ) {
                self.repository = repository
                self.coordinate = coordinate
                self.status = status
                self.readbackDigest = readbackDigest
                self.note = note
            }
        }

        public enum Error: Swift.Error, Equatable {
            case unknownStep(repository: String, coordinate: String)
            case preimageDrift(repository: String, expected: String, observed: String)
            case illegalTransition(from: Status, to: Status)
        }

        public let plan: Plan
        public private(set) var journal: [Entry]

        public init(plan: Plan) {
            self.plan = plan
            self.journal = plan.steps.map {
                Entry(repository: $0.repository, coordinate: $0.coordinate)
            }
        }

        /// Rehydrates an in-flight apply from its persisted journal —
        /// resume-not-restart. Journal rows must match the plan's steps.
        public init(plan: Plan, journal: [Entry]) throws(Error) {
            guard journal.count == plan.steps.count else {
                throw .unknownStep(repository: "journal", coordinate: "count \(journal.count) != \(plan.steps.count)")
            }
            for (step, entry) in zip(plan.steps, journal) {
                guard step.repository == entry.repository,
                      step.coordinate == entry.coordinate else {
                    throw .unknownStep(repository: entry.repository, coordinate: entry.coordinate)
                }
            }
            self.plan = plan
            self.journal = journal
        }

        public var nextPending: Plan.Step? {
            for (index, entry) in journal.enumerated()
            where entry.status == .pending || entry.status == .preimageVerified
                || entry.status == .written {
                return plan.steps[index]
            }
            return nil
        }

        public var terminal: Bool {
            journal.allSatisfy {
                $0.status == .readBack || $0.status == .rolledBack
            }
        }

        static let legal: [Status: Set<Status>] = [
            .pending: [.preimageVerified, .failed],
            .preimageVerified: [.written, .failed],
            .written: [.readBack, .failed],
            .failed: [.rolledBack],
            .readBack: [],
            .rolledBack: [],
        ]

        /// Verifies the live preimage against the plan before permitting
        /// the write; drift refuses (STOP-F14-PRODUCER shape).
        public mutating func verifyPreimage(
            repository: String, coordinate: String, observedDigest: String
        ) throws(Error) {
            let index = try index(repository: repository, coordinate: coordinate)
            let step = plan.steps[index]
            guard step.preimageDigest == observedDigest else {
                throw .preimageDrift(
                    repository: repository,
                    expected: step.preimageDigest, observed: observedDigest)
            }
            try transition(index, to: .preimageVerified)
        }

        public mutating func recordWrite(
            repository: String, coordinate: String
        ) throws(Error) {
            try transition(
                try index(repository: repository, coordinate: coordinate),
                to: .written)
        }

        public mutating func recordReadback(
            repository: String, coordinate: String, digest: String
        ) throws(Error) {
            let index = try index(repository: repository, coordinate: coordinate)
            try transition(index, to: .readBack)
            journal[index].readbackDigest = digest
        }

        public mutating func recordFailure(
            repository: String, coordinate: String, note: String
        ) throws(Error) {
            let index = try index(repository: repository, coordinate: coordinate)
            try transition(index, to: .failed)
            journal[index].note = note
        }

        public mutating func recordRollback(
            repository: String, coordinate: String
        ) throws(Error) {
            try transition(
                try index(repository: repository, coordinate: coordinate),
                to: .rolledBack)
        }

        func index(
            repository: String, coordinate: String
        ) throws(Error) -> Int {
            guard let index = journal.firstIndex(where: {
                $0.repository == repository && $0.coordinate == coordinate
            }) else {
                throw .unknownStep(repository: repository, coordinate: coordinate)
            }
            return index
        }

        mutating func transition(_ index: Int, to next: Status) throws(Error) {
            let current = journal[index].status
            guard Self.legal[current, default: []].contains(next) else {
                throw .illegalTransition(from: current, to: next)
            }
            journal[index].status = next
        }
    }
}
