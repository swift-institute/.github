extension PullRequest.Transaction.PostMerge {
    /// verify-post-merge.yml's entire report decision, serialized as one
    /// JSON object so the workflow step stays glue: branch on `outcome`,
    /// and file a Bug from `title`/`body` whenever it is not `"green"`.
    public struct Report: Codable, Equatable, Sendable {
        public let outcome: String
        public let title: String?
        public let body: String?

        public init(outcome: String, title: String?, body: String?) {
            self.outcome = outcome
            self.title = title
            self.body = body
        }
    }
}
