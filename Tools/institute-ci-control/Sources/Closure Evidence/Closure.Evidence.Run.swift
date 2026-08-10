extension Closure.Evidence {
    /// One cited run, resolved against GitHub's own run object. The
    /// resolution is the Application's; this type records only what the
    /// verdict needs: the run's own `conclusion` field and, per cited
    /// fix commit, where the run's head stands relative to it.
    public struct Run: Sendable, Equatable {
        public enum Conclusion: Sendable, Equatable {
            case success
            case failure
            case cancelled
            /// Any other terminal or non-terminal value GitHub reports
            /// (`skipped`, `timed_out`, `action_required`, in-progress
            /// null, …). None of them are evidence.
            case other(String)

            public init(name: String) {
                switch name {
                case "success": self = .success
                case "failure": self = .failure
                case "cancelled": self = .cancelled
                default: self = .other(name)
                }
            }
        }

        /// Where a run's head commit stands relative to one cited fix
        /// commit — the compare API's `status`, typed.
        public enum Ordering: Sendable, Equatable {
            /// The run's head is the cited commit or a descendant of it.
            case atOrAfter
            /// The run's head predates the cited commit: the run cannot
            /// have verified it.
            case before
            /// Diverged histories or a commit the repository does not
            /// contain.
            case unrelated
            /// The comparison could not be resolved.
            case unknown
        }

        public let reference: Citation.RunReference
        public let conclusion: Conclusion
        /// Ordering of this run's head against each cited commit, keyed
        /// by the cited (possibly abbreviated, lowercased) SHA.
        public let orderings: [String: Ordering]

        public init(
            reference: Citation.RunReference,
            conclusion: Conclusion,
            orderings: [String: Ordering] = [:]
        ) {
            self.reference = reference
            self.conclusion = conclusion
            self.orderings = orderings
        }
    }
}
