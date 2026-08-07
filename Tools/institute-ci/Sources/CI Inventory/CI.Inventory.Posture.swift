import CI_Contract

extension CI.Inventory {
    /// What one job of the universal workflow contributes to the verdict.
    ///
    /// The partition is derived from the two aggregates' own `needs:`
    /// lists rather than from a hand-kept table, so a job promoted from
    /// advisory to gating changes posture by being added to `ci-ok`'s
    /// needs — which is the only edit that actually changes the verdict.
    public enum Posture: String, Sendable, Equatable, CaseIterable {
        /// The planner. Runs first and selects the tier.
        case plan
        /// In `ci-ok`'s needs: its result can fail the required check.
        case gating
        /// In `advisory-summary`'s needs: reported, never gating.
        case advisory
        /// `ci-ok` or `advisory-summary` themselves.
        case aggregate
        /// Reached by neither aggregate — it runs on its own `if:` and
        /// reports only as its own check.
        case eventGated = "event-gated"
    }
}
