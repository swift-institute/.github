import CI_Contract

extension CI {
    /// The structural inventory of the shipped CI verdict — every job of
    /// the universal reusable workflow, its posture, its place in the
    /// DAG, its token boundary, and the aggregate that turns all of it
    /// into one required check.
    ///
    /// **This nest models the terminal one-hop topology.** A consumer
    /// repository's caller workflow `ci` runs one job, `matrix`, which
    /// `uses:` the universal `swift-ci.yml`; the universal's own `ci-ok`
    /// is the verdict, and the required check context is therefore
    /// exactly `ci / matrix / ci-ok` — the constant
    /// `CI.Contract.Requirement.checkContext` already owns.
    ///
    /// The retired `build-verdict-inventory.py` modelled a **three**-hop
    /// shape instead: universal → one layer wrapper per layer
    /// (`swift-primitives/.github`, `swift-standards/.github`,
    /// `swift-foundations/.github`) → caller, with an outer `ci-ok`
    /// trusting an inner one. Those wrappers no longer exist —
    /// `swift-primitives/.github` carries no `.github/workflows`
    /// directory at all — so the wrapper half of that inventory
    /// described nothing. It is not ported. Restoring a second hop would
    /// mean restoring the wrappers first, and that is the thing
    /// swift-institute/.github#358 removed.
    ///
    /// The inventory is **derived**, never hand-maintained: it is read
    /// out of the shipped YAML on demand, and the committed corpus is a
    /// regenerated expectation that a test compares against a freshly
    /// derived one. Drift between the workflow and its description is a
    /// test failure, not silent staleness.
    public enum Inventory {}
}
