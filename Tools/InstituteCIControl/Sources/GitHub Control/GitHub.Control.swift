import GitHub

// Nest.Name namespace shell (FT1-ratification.json). `GitHub.Control`
// composes the canonical swift-github / swift-github-http owners with
// the control plane's App capabilities, pagination, retry and
// idempotency. It is never linked into ordinary/fork execution.
extension GitHub {
    public enum Control {}
}
