extension PRTransaction.PostMerge {
    /// The exhaustive classification of one post-merge watch. A lost watch
    /// is not-green: every case other than `.green` files a Bug on the
    /// drained repository, exactly as a confirmed red run does.
    public enum Outcome: Equatable, Sendable {
        /// The dispatched run reached its own terminal `success` conclusion
        /// at the exact expected head.
        case green(runURL: String)

        /// The dispatched run reached a terminal conclusion other than
        /// `success` at the exact expected head.
        case red(conclusion: String, runURL: String)

        /// The watch itself never reached a confirmed conclusion — neither
        /// red nor green is known. `reason` names the failure class for the
        /// Bug body; it never gates whether the Bug is filed.
        case lost(reason: Reason)
    }
}
