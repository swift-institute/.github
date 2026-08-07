extension PullRequest.Transaction.Snapshot.Source {
    /// The caller-accepted exact-revision plan supplied to the snapshot producer.
    public struct Plan: Codable, Sendable {
        public let accepted: Bool
        public let repository: String
        public let pull: Int
        public let base: String
        public let head: String
        public let task: PullRequest.Transaction.Snapshot.Issue
        public let verification: PullRequest.Transaction.Snapshot.Verification
        public let paths: [String]
        public let evidence: [PullRequest.Transaction.Snapshot.Evidence]
        public let payloadPreflighted: Bool
        public let nextOwner: String
    }
}
