extension Repository.Policy.Approval.Caller {
    struct CreatePull: Encodable {
        let title: String
        let body: String
        let head: String
        let base: String
    }
}
