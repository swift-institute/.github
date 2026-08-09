extension PullRequest.Transaction.Snapshot.Source {
    /// The target identity returned by the repository API.
    public struct Target: Codable, Sendable {
        public let repository: String
        public let visibility: PullRequest.Transaction.Snapshot.Visibility
    }
}
