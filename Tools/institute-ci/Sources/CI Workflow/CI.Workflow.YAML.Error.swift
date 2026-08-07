import CI_Contract

extension CI.Workflow.YAML {
    /// The one failure the reader can produce: the document used a
    /// construct outside the bounded Actions subset.
    ///
    /// There is no `.malformed` case. A bounded reader that guesses at
    /// what it does not cover is worse than one that refuses, because a
    /// guess reaches a rule predicate as a plausible-looking wrong
    /// document. Every refusal names its line and its construct so the
    /// subset can be widened deliberately.
    public enum Error: Swift.Error, Sendable, Equatable {
        case unsupported(line: Int, construct: String)

        public var message: String {
            switch self {
            case .unsupported(let line, let construct):
                "line \(line): unsupported YAML construct — \(construct)"
            }
        }
    }
}
