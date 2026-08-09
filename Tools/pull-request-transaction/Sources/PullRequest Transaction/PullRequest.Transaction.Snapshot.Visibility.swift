extension PullRequest.Transaction.Snapshot {
    /// The closed repository-visibility set the approval transaction governs.
    public enum Visibility: String, Codable, Equatable, Sendable {
        case `public`
        case `private`
    }
}
