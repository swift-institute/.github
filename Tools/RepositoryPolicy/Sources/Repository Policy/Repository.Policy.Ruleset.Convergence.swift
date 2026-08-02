import Foundation

extension RepositoryPolicy.Ruleset {
    /// Which posture the `rulesets` job runs under when an Institute ruleset
    /// (of either class) is absent from a target repository
    /// (swift-institute/.github#204).
    ///
    /// The posture never changes how an EXISTING ruleset is handled — that
    /// path (re-apply the class-correct contract, read back, report drift)
    /// is identical under both cases. The only thing a `SweepMode` decides
    /// is whether an absent ruleset may be created.
    public enum SweepMode: String, Codable, Equatable, Sendable {
        /// The nightly/scheduled posture: re-applies the class-correct
        /// contract over an Institute ruleset that already exists (drift
        /// repair) but never creates one where none exists. First
        /// application on a previously unenforced repository stays excluded
        /// from the scheduled path.
        case scheduledHeal = "scheduled-heal"
        /// The `apply-rulesets: true` explicit, deliberate-dispatch posture
        /// (swift-institute/.github#193): may create a first ruleset on a
        /// repository that has none, in addition to healing existing ones.
        case explicitApply = "explicit-apply"
    }

    /// The mechanical action the `rulesets` job takes for one repository,
    /// given whether an Institute ruleset already exists there.
    public enum ConvergenceAction: String, Codable, Equatable, Sendable {
        /// An Institute ruleset already exists (same class, or a class
        /// flip): re-apply the class-correct contract and read it back.
        /// Valid, and identical, under both sweep modes.
        case reapply
        /// No Institute ruleset exists and the sweep runs under explicit
        /// opt-in: create it (the swift-institute/.github#193 first-
        /// application path).
        case create
        /// No Institute ruleset exists and the sweep runs under the
        /// scheduled/nightly posture: first application stays excluded from
        /// the scheduled path. Reported, never enrolled implicitly.
        case skipAbsentOnSchedule
    }

    /// A typed report of the convergence decision for one repository.
    public struct ConvergenceDecision: Codable, Equatable, Sendable {
        public let action: ConvergenceAction
        public let reason: String

        public init(action: ConvergenceAction, reason: String) {
            self.action = action
            self.reason = reason
        }
    }

    /// The heal-existing-vs-skip-absent decision itself
    /// (swift-institute/.github#204). Pure: independent of the network I/O
    /// that resolves `rulesetExists` and of the class-correct contract
    /// payload and its read-back, both of which stay exactly as they were —
    /// this function only ever gates whether a first CREATE may run. An
    /// already-existing ruleset always proceeds to re-apply and read-back,
    /// under either posture, so fail-closed classification and read-back
    /// semantics are unchanged by this decision.
    public static func decideConvergence(
        rulesetExists: Bool,
        mode: SweepMode
    ) -> ConvergenceDecision {
        guard rulesetExists else {
            switch mode {
            case .explicitApply:
                return ConvergenceDecision(
                    action: .create,
                    reason:
                        "no Institute ruleset exists; the explicit apply-rulesets opt-in permits first application"
                )
            case .scheduledHeal:
                return ConvergenceDecision(
                    action: .skipAbsentOnSchedule,
                    reason:
                        "no Institute ruleset exists; first application stays excluded from the scheduled path (explicit opt-in only)"
                )
            }
        }
        return ConvergenceDecision(
            action: .reapply,
            reason: "an Institute ruleset already exists; re-applying the class-correct contract"
        )
    }
}
