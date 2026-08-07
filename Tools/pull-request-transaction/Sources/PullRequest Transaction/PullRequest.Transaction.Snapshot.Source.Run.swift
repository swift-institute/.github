extension PullRequest.Transaction.Snapshot.Source {
    /// One workflow run returned by the actions API, with its triggering event.
    public struct Run: Codable, Sendable {
        public let name: String
        public let event: String
        public let head: String
        public let conclusion: String?
    }
}
