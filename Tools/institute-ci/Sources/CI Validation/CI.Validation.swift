import CI_Contract

// Nest.Name namespace shell (FT1-ratification.json;
// naming-annex-nest-name.md).
//
// `CI.Validation` owns the *predicate* half of the validator contract —
// what a rule is, what it is run against, what it emits, and how an
// implementation is proved. It is the Swift expression of the contract
// that `.github/scripts/validate_lib.py` held for the retired Python
// corpus:
//
//   emit()                       → `Finding` and its TSV encoding
//   require_yaml() / exit 2      → `EnvironmentDefect`
//   load_workflow_yaml_or_emit() → `Subject.workflows()`
//   parse_on_block/iter_jobs     → `CI.Workflow.Document` accessors
//
// A rule implementation declares a `Validator`; it never prints, never
// exits, and never reads argv.
extension CI {
    public enum Validation {}
}
