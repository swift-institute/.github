import GitHub

// Nest.Name namespace shell (FT1-ratification.json). `GitHub.Control`
// composes the canonical swift-github / swift-github-http owners with
// the control plane's App capabilities, retry and idempotency.
// Pagination stays with the canonical owners: swift-github's
// Client+all traversal and swift-github-http's Link witness.
// It is never linked into ordinary/fork execution.
extension GitHub {
    public enum Control {}
}
