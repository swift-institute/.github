extension Repository.Policy.Approval.Caller {
    struct Content: Decodable {
        let encoding: String?
        let content: String?
        let sha: String?
    }
}
