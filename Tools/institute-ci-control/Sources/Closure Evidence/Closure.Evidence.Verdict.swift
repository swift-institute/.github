extension Closure.Evidence {
    /// The ratified predicate over one completed closure's resolved
    /// citations (swift-institute/.github#512).
    public enum Verdict: Sendable, Equatable {
        /// A cited run's own `conclusion` is success and its head is
        /// at-or-after every cited fix commit.
        case compliant(Citation.RunReference)
        case violation(Reason)

        public enum Reason: Sendable, Equatable {
            /// No run URL was cited at all. `commitCited` distinguishes
            /// the triage class — "fix pushed at <SHA>" with no run —
            /// from a closure citing nothing.
            case noRunCited(commitCited: Bool)
            /// A cited run resolved with `conclusion` failure and no
            /// cited run succeeded: the claimed fix is observed broken.
            case citedRunFailed(Citation.RunReference)
            /// The best cited run's conclusion is neither success nor
            /// failure — cancelled runs and the rest are not evidence.
            case citedRunNotEvidence(Citation.RunReference, String)
            /// A cited run succeeded, but its head predates (or is
            /// unrelated to) a cited fix commit, so it cannot have
            /// verified that commit.
            case runPredatesCitedCommit(Citation.RunReference, commit: String)
            /// No cited run could be resolved to a run object.
            case runUnresolvable(Citation.RunReference)
        }

        /// Judge one closure. `runs` carries every cited run that
        /// resolved; `unresolved` the cited references that did not;
        /// `commitCited` whether any fix-commit SHA was cited.
        public static func of(
            runs: [Run],
            unresolved: [Citation.RunReference],
            commitCited: Bool
        ) -> Verdict {
            if runs.isEmpty && unresolved.isEmpty {
                return .violation(.noRunCited(commitCited: commitCited))
            }

            // A success whose orderings are all at-or-after is evidence;
            // one bad ordering disqualifies that run but records why.
            var predated: (Citation.RunReference, String)?
            var failed: Citation.RunReference?
            var inconclusive: (Citation.RunReference, String)?
            for run in runs {
                switch run.conclusion {
                case .success:
                    if let offending = run.orderings.first(where: { $0.value != .atOrAfter }) {
                        if predated == nil { predated = (run.reference, offending.key) }
                    } else {
                        return .compliant(run.reference)
                    }
                case .failure:
                    if failed == nil { failed = run.reference }
                case .cancelled:
                    if inconclusive == nil { inconclusive = (run.reference, "cancelled") }
                case .other(let name):
                    if inconclusive == nil { inconclusive = (run.reference, name) }
                }
            }

            if let failed { return .violation(.citedRunFailed(failed)) }
            if let (reference, commit) = predated {
                return .violation(.runPredatesCitedCommit(reference, commit: commit))
            }
            if let (reference, name) = inconclusive {
                return .violation(.citedRunNotEvidence(reference, name))
            }
            return .violation(.runUnresolvable(unresolved[0]))
        }
    }
}
