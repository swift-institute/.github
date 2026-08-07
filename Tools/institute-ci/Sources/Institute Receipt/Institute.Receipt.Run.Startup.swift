extension Institute.Receipt.Run {
    /// The probe for runs that never started.
    ///
    /// A `startup_failure` is invisible to every per-job gate, because
    /// no job runs: the run concludes before the workflow is loaded, the
    /// jobs collection is empty, and there are no logs to fetch. Nothing
    /// downstream can notice it, so a scheduled scan over recent runs is
    /// the only place the class can be seen at all — hence a weekly
    /// probe rather than a check.
    ///
    /// The predicate is one typed comparison, and it is kept a value
    /// rather than a free function so the count it was drawn from
    /// travels with the finding: "0 flagged" means nothing without
    /// "of how many", and a probe that scanned zero runs and reported
    /// clean is the false green this exists to prevent.
    public struct Startup: Sendable, Equatable {
        public let inspected: [Summary]

        public init(scanning inspected: [Summary]) {
            self.inspected = inspected
        }
    }
}

extension Institute.Receipt.Run.Startup {
    /// The runs that concluded `startup_failure`.
    ///
    /// Exactly that conclusion and no other: `nil` is an in-flight
    /// run, and every other terminal state means the workflow did
    /// load.
    public var flagged: [Institute.Receipt.Run.Summary] {
        inspected.filter { $0.conclusion == .startupFailure }
    }

    /// Whether the scan found nothing to flag.
    public var isClean: Bool { flagged.isEmpty }

}
