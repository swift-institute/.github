import Foundation

extension Repository.Policy {
    /// Whether a fleet repository is eligible for the generated terminal
    /// caller wave.
    ///
    /// The F14 wave proved the predicate empirically, in both directions
    /// (swift-institute/.github#394 comment 5205766701):
    ///
    /// - "has a `ci.yml`" is WRONG in the *omission* direction. Five
    ///   unarchived repositories carried a root `Package.swift` and no
    ///   `ci.yml`; a `ci.yml`-keyed wave leaves each one permanently
    ///   unconverged and invisible to a convergence count keyed on
    ///   callers.
    /// - "has a root `Package.swift`" alone is WRONG in the *destructive*
    ///   direction. Two dry-run iterations caught it about to overwrite
    ///   genuinely bespoke CI on `swift-institute/Issues` (100 lines → 26)
    ///   and `swift-institute/Skills` (67 → 25). Both carry a root
    ///   manifest *and* `uses:` an Institute reusable workflow, so no
    ///   workflow-shape probe distinguishes them either. Their CI is a
    ///   per-reproducer matrix, not a fleet caller.
    ///
    /// The correct predicate is therefore: **root `Package.swift`, minus a
    /// typed bespoke-CI exception set.** That exception is a repository
    /// fact and belongs here, where it is data with tests, rather than in
    /// a shell script where it is re-derived by hand on every run
    /// (F16 hoist; swift-institute/.github#404).
    ///
    /// This owner classifies; it does not discover. `rootManifest` is a
    /// measured fact supplied by the caller, and an *unmeasured* manifest
    /// is not a negative — see `Eligibility.Subject.rootManifest`.
    public enum Eligibility {
        /// Repositories that carry a root `Package.swift` and whose CI is
        /// nonetheless bespoke by ruling. Membership is a decision about
        /// that repository's CI ownership, never an inference from its
        /// shape — every entry names the ruling that put it here.
        ///
        /// Compared case-insensitively on the full `owner/name`
        /// coordinate, because GitHub repository names are
        /// case-insensitive and a case-mismatched miss here converges
        /// bespoke CI away.
        public static let bespoke: [Repository.Policy.Eligibility.Exception] = [
            .init(
                repository: "swift-institute/Issues",
                reason: """
                    Isolated Swift compiler and toolchain reproducers. CI is a \
                    per-reproducer matrix, not a fleet caller. Ruled the single \
                    TERMINAL_UNGATED exception by the F14 wave \
                    (swift-institute/.github#394 comment 5207423211).
                    """
            ),
            .init(
                repository: "swift-institute/Skills",
                reason: """
                    Skill-corpus hygiene CI, bespoke by ruling. Caught in the \
                    F14 dry run at 67 lines → 25 \
                    (swift-institute/.github#394 comment 5205766701). Carries \
                    NO root Package.swift at the time of this hoist, so the \
                    manifest term already excludes it and this entry changes \
                    no present outcome; it is here so that adding a manifest \
                    later cannot silently admit it to the wave.
                    """
            ),
        ]

        /// The wave verdict for one subject.
        ///
        /// The manifest term is evaluated first, so a repository with no
        /// root manifest reports `.noManifest` — the reason it is actually
        /// out of the wave — even when it also carries an exception. The
        /// exception then reports only for subjects the manifest term
        /// would otherwise admit, which is the only case where it changes
        /// an outcome.
        public static func verdict(
            _ subject: Repository.Policy.Eligibility.Subject
        ) -> Repository.Policy.Eligibility.Verdict {
            switch subject.rootManifest {
            case .absent:
                return .noManifest
            case .present:
                if let exception = exception(subject.repository) {
                    return .bespoke(exception)
                }
                return .eligible
            }
        }

        /// The matching exception, if the repository carries one. Exposed
        /// so a caller can report *which* ruling excluded a subject rather
        /// than only that something did.
        public static func exception(
            _ repository: String
        ) -> Repository.Policy.Eligibility.Exception? {
            bespoke.first {
                $0.repository.compare(repository, options: [.caseInsensitive]) == .orderedSame
            }
        }
    }
}
