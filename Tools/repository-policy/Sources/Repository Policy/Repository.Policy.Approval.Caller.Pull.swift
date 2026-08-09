extension Repository.Policy.Approval.Caller {
    struct Pull: Decodable {
        let number: Int
        let state: String
        let head: Branch
        let base: Branch
    }
}
