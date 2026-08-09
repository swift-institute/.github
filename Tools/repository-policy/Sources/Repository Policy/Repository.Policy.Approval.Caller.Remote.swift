extension Repository.Policy.Approval.Caller {
    struct Remote: Decodable {
        let visibility: String
        let archived: Bool
        let defaultBranch: String

        enum CodingKeys: String, CodingKey {
            case visibility
            case archived
            case defaultBranch = "default_branch"
        }
    }
}
