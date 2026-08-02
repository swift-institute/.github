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
        public let checks: [Check]
        public let unresolvedThreads: Int
        public let merge: Merge

        /// Binds the accepted plan's exact Issue and profile into its preflighted payload.
        public func snapshot() -> PRTransaction.Snapshot {
            PRTransaction.Snapshot(
                repository: repository,
                pull: pull,
                base: base,
                head: head,
                fixer: fixer,
                owningTask: owningTask,
                plan: PRTransaction.Snapshot.Plan(
                    accepted: plan.accepted,
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
                checks: checks,
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
    }
}
