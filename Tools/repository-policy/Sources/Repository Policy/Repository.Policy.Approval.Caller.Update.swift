extension Repository.Policy.Approval.Caller {
    struct Update: Encodable {
        let message: String
        let content: String
        let branch: String
        let sha: String?
    }
}
