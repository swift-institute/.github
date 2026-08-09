extension PullRequest.Transaction.Snapshot.Source {
    /// One workflow run returned by the actions API, with its triggering event.
    public struct Run: Codable, Sendable {
        public let id: Int64
        public let attempt: Int
        public let startedAt: String
        public let name: String
        public let event: String
        public let head: String
        public let conclusion: String?
    }
}
