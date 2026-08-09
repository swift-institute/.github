extension Repository.Policy.Approval.Caller {
    public enum Decision: Sendable, Equatable {
        case converged
        case pullRequest(base: String, revision: String?)
    }
}
