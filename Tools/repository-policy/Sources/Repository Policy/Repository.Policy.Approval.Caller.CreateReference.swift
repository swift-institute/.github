extension Repository.Policy.Approval.Caller {
    struct CreateReference: Encodable {
        let ref: String
        let sha: String
    }
}
