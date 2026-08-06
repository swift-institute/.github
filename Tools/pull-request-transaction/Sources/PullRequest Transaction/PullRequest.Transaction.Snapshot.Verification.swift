extension PullRequest.Transaction.Snapshot {
    /// The exact-head checks an accepted pull-request transaction requires.
    public enum Verification: Codable, Equatable, Sendable {
        /// Requires successful exact-head `ci / matrix / ci-ok` and
        /// `full-tier` results. Public package profile only
        /// (swift-institute/.github#276 Task 3-01); a private package's
        /// `verification / workspace` receipt is verified through
        /// `.control(checks:)` with that name declared explicitly.
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

        /// The mechanical-remediation fast lane (swift-institute/.github#211).
        /// Requires every named repository-native check to succeed at the
        /// exact head, exactly like `control` — deliberately without a
        /// synthesized `full-tier` requirement, since the mandatory
        /// post-merge full tier (verify-post-merge.yml) is the deferred
        /// gate this profile exists to move off the review path. Admissible
        /// only when `mechanical` attests the mechanical-remediation class;
        /// a plan selecting this profile without that attestation fails
        /// closed exactly as an absent or malformed check list does.
        case waveMechanical(checks: [String], mechanical: Bool)
    }
}
