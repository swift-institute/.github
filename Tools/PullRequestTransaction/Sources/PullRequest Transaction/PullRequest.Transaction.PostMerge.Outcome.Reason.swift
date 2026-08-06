extension PullRequest.Transaction.PostMerge.Outcome {
    /// The specific way a post-merge watch was lost, named in the Bug body
    /// so the class — not just the fact of loss — reaches whoever triages
    /// it.
    public enum Reason: String, Equatable, Sendable {
        /// The dispatch step itself did not complete successfully — most
        /// commonly the job's own `timeout-minutes` expiring, or the step
        /// otherwise being cancelled, while the awaited run was still in
        /// flight.
        case watchCancelled = "watch-cancelled"

        /// The dispatch step exited abnormally for a reason other than
        /// cancellation (an unhandled error in the dispatch/poll script).
        case watchFailed = "watch-failed"

        /// No `workflow_dispatch` run of the drained repository's `ci.yml`
        /// at the exact expected head was discovered within the discovery
        /// window — including the dispatch/discovery race where a run
        /// lands at a newer commit than the one this watch expected.
        case runNotDiscovered = "run-not-discovered"

        /// The discovered run did not reach a terminal status before this
        /// watch's own internal poll bound. That bound is set below the
        /// job's `timeout-minutes`, so this case is reached deliberately,
        /// never by the job being killed out from under the script.
        case pollTimedOut = "poll-timed-out"
    }
}
