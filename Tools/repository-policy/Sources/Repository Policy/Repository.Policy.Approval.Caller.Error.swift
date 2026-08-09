extension Repository.Policy.Approval.Caller {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidTarget(Int)
        case duplicateTarget(Int)
        case operation(Int)
    }
}

extension Repository.Policy.Approval.Caller.Error {
    public var description: String {
        switch self {
        case .invalidTarget(let ordinal):
            "target #\(ordinal): not an active private default-branch repository"
        case .duplicateTarget(let ordinal):
            "target #\(ordinal): duplicate runner-local target"
        case .operation(let ordinal):
            "target #\(ordinal): caller pull request could not be converged"
        }
    }
}
