extension Repository.Policy.Census {
    /// The coordinate kinds of the FT1 census schema.
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case file
        case runBlock = "run-block"
        case expression
        case usesEdge = "uses-edge"
        case commandReference = "command-reference"
        case family
    }
}
