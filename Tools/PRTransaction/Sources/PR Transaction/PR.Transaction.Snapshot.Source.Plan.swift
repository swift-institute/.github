extension PRTransaction.Snapshot.Source {
    /// The caller-accepted exact-revision plan supplied to the snapshot producer.
    public struct Plan: Codable, Sendable {
        public let accepted: Bool
        public let base: String
        public let head: String
        public let task: PRTransaction.Snapshot.Issue
        public let verification: PRTransaction.Snapshot.Verification
        public let paths: [String]
        public let evidence: [PRTransaction.Snapshot.Evidence]
        public let payloadPreflighted: Bool
        public let nextOwner: String
    }
}
