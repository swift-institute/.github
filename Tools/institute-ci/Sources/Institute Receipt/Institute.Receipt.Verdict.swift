extension Institute.Receipt {
    /// What a receipt attests.
    ///
    /// `unmeasured` is the load-bearing case and the reason this is not
    /// a boolean. The historical false-success variant reported a clean
    /// verdict over an empty reusable-workflow chain — evidence that was
    /// never gathered, reported as evidence that passed. A measurement
    /// gap is its own answer, distinct from both `met` and `failed`, and
    /// it is never repaired by a read of current `main`.
    public enum Verdict: String, Sendable, Equatable {
        /// The producing run is still in flight; no terminal claim.
        case preterminal
        /// A required identity family was not measurable (P20).
        case unmeasured = "UNMEASURED"
        /// The run concluded success and every mandatory selected job
        /// concluded success.
        case met = "MET"
        case failed = "FAILED"
    }
}
