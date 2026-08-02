extension PRTransaction.Snapshot {
    /// The exact-head checks an accepted pull-request transaction requires.
    public enum Verification: Codable, Equatable, Sendable {
        /// Requires successful exact-head `ci-ok` and `full-tier` results.
        case `package`

        /// Requires every named repository-native check to succeed at the exact head.
        case control(checks: [String])
    }
}
