extension Repository.Policy.Approval.Caller.Pull {
    struct Branch: Decodable {
        let ref: String
        let sha: String
    }
}
