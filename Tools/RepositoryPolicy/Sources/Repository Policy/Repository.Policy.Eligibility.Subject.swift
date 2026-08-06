extension Repository.Policy.Eligibility {
    /// One repository as the eligibility predicate sees it: its coordinate
    /// plus the single measured fact the predicate consumes.
    public struct Subject: Sendable, Equatable {
        /// Whether the repository's default branch carries a root
        /// `Package.swift`.
        ///
        /// There are exactly two cases and no third, because there is no
        /// safe default for "not measured". A 404 from a contents read is
        /// `.absent` only when the read itself succeeded; a read that
        /// failed for any other reason — rate limit, auth, network, a
        /// deleted repository — is not a measurement and must not be
        /// funnelled into `.absent`. The F14 census hit exactly this: a
        /// probe that treated jq's `null` on a 404 as a hit reported all
        /// 22 candidates eligible (swift-institute/.github#394 comment
        /// 5205766701). A caller that cannot measure has no `Subject` to
        /// build and must report UNMEASURED rather than construct one.
        public enum Manifest: Sendable, Equatable {
            case present
            case absent
        }

        /// The full `owner/name` coordinate.
        public let repository: String
        public let rootManifest: Manifest

        public init(repository: String, rootManifest: Manifest) {
            self.repository = repository
            self.rootManifest = rootManifest
        }
    }
}
