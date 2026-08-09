extension Repository.Policy.Approval.Caller {
    struct Comparison: Decodable {
        let status: String
        let aheadBy: Int
        let behindBy: Int
        let files: [File]

        enum CodingKeys: String, CodingKey {
            case status
            case aheadBy = "ahead_by"
            case behindBy = "behind_by"
            case files
        }
    }
}
