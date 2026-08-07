extension Repository.Policy.Eligibility {
    /// Why a subject is in, or out of, the generated terminal caller wave.
    ///
    /// The two exclusions stay distinct rather than collapsing to one
    /// `ineligible` case. They have different consequences: `.noManifest`
    /// says the wave has nothing to converge, while `.bespoke` says the
    /// wave has something to converge and is forbidden from touching it.
    /// A count that merges them cannot tell an unconverged omission from a
    /// protected repository.
    public enum Verdict: Sendable, Equatable {
        /// Root manifest present, no exception: render and converge.
        case eligible
        /// Root manifest present, but CI is bespoke by the named ruling.
        case bespoke(Repository.Policy.Eligibility.Exception)
        /// No root `Package.swift` on the default branch.
        case noManifest

        public var isEligible: Bool {
            self == .eligible
        }
    }
}
