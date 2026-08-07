import CI_Contract

// Nest.Name namespace shell (FT1-ratification.json;
// naming-annex-nest-name.md). `CI.Workflow` owns the *document* half of
// the validator contract: reading a GitHub Actions workflow file into a
// typed value. Rule predicates over that value belong to `CI.Validation`;
// subject/event/plan/aggregate semantics stay in `CI.Contract`.
extension CI {
    public enum Workflow {}
}
