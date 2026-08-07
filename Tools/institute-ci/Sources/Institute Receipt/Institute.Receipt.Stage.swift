extension Institute.Receipt {
    /// Which half of the two-phase attestation a record is.
    ///
    /// The split is not bookkeeping: an aggregate job observing its own
    /// run cannot see that run's conclusion, so a record minted in-run
    /// may never claim one. `preterminal` is the record that admits
    /// this; `terminal` is the collector's record, and it is terminal
    /// only because it carries the digest of the preterminal record it
    /// augments.
    public enum Stage: String, Sendable, Equatable {
        case preterminal
        case terminal
    }
}
