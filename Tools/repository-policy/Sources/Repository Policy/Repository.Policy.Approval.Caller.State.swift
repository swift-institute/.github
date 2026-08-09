extension Repository.Policy.Approval.Caller {
    public struct State: Sendable, Equatable {
        public let visibility: String
        public let archived: Bool
        public let branch: String
        public let file: File?

        public init(
            visibility: String,
            archived: Bool,
            branch: String,
            file: File?
        ) {
            self.visibility = visibility
            self.archived = archived
            self.branch = branch
            self.file = file
        }
    }
}
