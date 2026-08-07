import CI_Contract

extension CI.Validation {
    /// Rules whose subject is a **hand-synchronised copy**.
    ///
    /// Actions makes some correspondences impossible to derive at run
    /// time: `on.workflow_run.workflows:` must name its subjects
    /// literally, and a report job that summarises N scan legs repeats
    /// their roster across `needs:`, an `if:` guard, an env block, a
    /// shell loop, and a heredoc. Each of those is a second copy of a
    /// fact the workflow already states, and a second copy drifts.
    ///
    /// Both members here discover the roster from the workflow's own
    /// `jobs:` or from the workflows directory — **never** from a
    /// hard-coded list, which would just be a third copy — and assert the
    /// derived set against the hand-maintained one in both directions.
    /// Each has drifted in production at least once, which is why they
    /// exist rather than a review convention.
    ///
    /// The leaf names transliterate their rule identifiers
    /// (`LINT-VALIDATORS-WEEKLY-DRIFT`, `SCHEDULED-WORKFLOW-ALERT-DRIFT`),
    /// which are the join key between a finding, the fixture corpus,
    /// `validators-manifest.yaml`, and `validate-base.yml`'s aggregation
    /// regex; a name chosen independently of the identifier would be a
    /// fifth spelling of the same thing.
    public enum Drift {}
}
