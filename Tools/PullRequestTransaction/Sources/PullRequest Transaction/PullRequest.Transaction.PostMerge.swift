extension PullRequest.Transaction {
    /// The deferred post-merge full-tier watch (verify-post-merge.yml,
    /// swift-institute/.github#211, #213): classifies one dispatched-and-
    /// awaited run into a not-green outcome that always files a Bug on the
    /// drained repository, or a green outcome that never does.
    public enum PostMerge {}
}
