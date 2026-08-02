extension PRTransaction.Snapshot {
    /// The live repository data and accepted plan used to produce a guarded snapshot.
    public struct Source: Codable, Sendable {
        public let repository: String
        public let pull: Int
        public let base: String
        public let head: String
        public let fixer: String
        public let owningTask: Issue
        public let plan: Plan
        public let reviews: [Review]
        public let checkPages: [Page<Check>]
        public let runPages: [Page<Check>]
        public let unresolvedThreads: Int
        public let merge: Merge

        /// Combines complete API pages and binds the plan into its preflighted payload.
        public func snapshot() throws(PRTransaction.Error) -> PRTransaction.Snapshot {
            let checks = try collect(checkPages, name: "check-runs")
            let runs = try collect(runPages, name: "workflow-runs")
            return PRTransaction.Snapshot(
                repository: repository,
                pull: pull,
                base: base,
                head: head,
                fixer: fixer,
                owningTask: owningTask,
                plan: PRTransaction.Snapshot.Plan(
                    accepted: plan.accepted,
                    repository: plan.repository,
                    pull: plan.pull,
                    base: plan.base,
                    head: plan.head,
                    fixer: fixer,
                    task: plan.task,
                    verification: plan.verification,
                    paths: plan.paths,
                    evidence: plan.evidence,
                    payload: PRTransaction.Snapshot.Payload(
                        preflighted: plan.payloadPreflighted,
                        head: plan.head,
                        verification: plan.verification
                    ),
                    nextOwner: plan.nextOwner
                ),
                reviews: reviews,
                checks: checks
                    + runs.filter { $0.name == "swift-ci" }.map {
                        Check(name: "full-tier", head: $0.head, conclusion: $0.conclusion)
                    },
                unresolvedThreads: unresolvedThreads,
                merge: merge,
                receipt: PRTransaction.Snapshot.Receipt(
                    complete: false,
                    head: head,
                    issueClosed: false,
                    unassigned: false
                )
            )
        }

        private func collect<Element: Codable & Sendable>(
            _ pages: [Page<Element>],
            name: String
        ) throws(PRTransaction.Error) -> [Element] {
            let values = pages.flatMap(\.values)
            guard let total = pages.first?.total,
                total >= 0,
                pages.allSatisfy({ $0.total == total }),
                values.count == total
            else {
                throw PRTransaction.Error.incomplete(name)
            }
            return values
        }
    }
}
