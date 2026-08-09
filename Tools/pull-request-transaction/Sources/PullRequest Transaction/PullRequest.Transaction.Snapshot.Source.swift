extension PullRequest.Transaction.Snapshot {
    /// The live repository data and accepted plan used to produce a guarded snapshot.
    public struct Source: Codable, Sendable {
        public let repository: String
        public let target: Target
        public let pull: Int
        public let base: String
        public let head: String
        public let fixer: String
        public let owningTask: Issue
        public let plan: Plan
        public let reviews: [Review]
        public let checkPages: [Page<Check>]
        public let runPages: [Page<Run>]
        public let unresolvedThreads: Int
        public let merge: Merge

        /// Combines complete API pages and binds the plan into its preflighted payload.
        public func snapshot() throws(PullRequest.Transaction.Error) -> PullRequest.Transaction.Snapshot {
            guard target.repository == repository else {
                throw PullRequest.Transaction.Error.invalidTarget
            }
            let checks = try collect(checkPages, name: "check-runs")
            let runs = try collect(runPages, name: "workflow-runs")
            return PullRequest.Transaction.Snapshot(
                repository: repository,
                visibility: target.visibility,
                pull: pull,
                base: base,
                head: head,
                fixer: fixer,
                owningTask: owningTask,
                plan: PullRequest.Transaction.Snapshot.Plan(
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
                    payload: PullRequest.Transaction.Snapshot.Payload(
                        preflighted: plan.payloadPreflighted,
                        head: plan.head,
                        verification: plan.verification
                    ),
                    nextOwner: plan.nextOwner
                ),
                reviews: reviews,
                checks: checks
                    // The full tier is the `workflow_dispatch` run of the fleet
                    // thin caller, which every package repository names `CI`.
                    // Runs of the same workflow for other events are lower tiers
                    // and are not full-tier evidence.
                    + runs.filter { $0.name == "CI" && $0.event == "workflow_dispatch" }.map {
                        Check(name: "full-tier", head: $0.head, conclusion: $0.conclusion)
                    },
                unresolvedThreads: unresolvedThreads,
                merge: merge,
                receipt: PullRequest.Transaction.Snapshot.Receipt(
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
        ) throws(PullRequest.Transaction.Error) -> [Element] {
            let values = pages.flatMap(\.values)
            guard let total = pages.first?.total,
                total >= 0,
                pages.allSatisfy({ $0.total == total }),
                values.count == total
            else {
                throw PullRequest.Transaction.Error.incomplete(name)
            }
            return values
        }
    }
}
