extension PRTransaction.Snapshot {
    /// The exact-head checks an accepted pull-request transaction requires.
    public enum Verification: Codable, Equatable, Sendable {
        /// Requires successful exact-head `ci / ci-ok` and `full-tier` results.
        case `package`

        /// Requires every named repository-native check to succeed at the exact head.
        case control(checks: [String])

        /// Reserved for legitimately check-less PRs (a path outside every
        /// path-filtered workflow's trigger — e.g. a Tools-only change in
        /// this repository, swift-institute/.github#200). Satisfied only
        /// when the exact-head check-run collection is empty; any check run
        /// present at the head — including a synthesized `full-tier` run —
        /// fails it closed, since that would be an uncited check standing in
        /// for a review this profile does not admit.
        case reviewOnly
    }
}
