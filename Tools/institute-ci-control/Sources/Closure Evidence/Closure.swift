// Nest.Name namespace shell. `Closure.Evidence` owns the ratified
// closure-evidence predicate (swift-institute/.github#512): a completed
// issue closure must cite an Actions run URL whose own `conclusion` is
// success at-or-after any cited fix commit. A commit SHA alone is not
// closure evidence, and a cancelled run is not evidence.
//
// Everything here is pure. The credentialed edge — enumerating closed
// issues, reading comments, resolving cited runs and commit orderings —
// lives in `Institute.CI.Control.Application.ClosureEvidence`, which
// supplies recorded facts to the verdict. That seam is why this target's
// tests need no network and no token.
public enum Closure {}

extension Closure {
    /// The completed-closure evidence contract: what a closing comment
    /// may cite, what a cited run resolves to, and the verdict over the
    /// resolved facts.
    public enum Evidence {}
}
