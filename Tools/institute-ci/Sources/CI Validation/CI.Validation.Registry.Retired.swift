import CI_Contract

extension CI.Validation.Registry {
    /// The validator that has replaced a retired Python script, or `nil`
    /// when that script has no Swift owner yet.
    ///
    /// This is the **cutover mechanism**. `validate-base.yml` is handed a
    /// *script path* — `.github/scripts/validate-cache-policy.py` — not a
    /// rule identifier, because that is what its fifty callers declare.
    /// So the workflow cannot ask the rule-indexed registry anything, and
    /// the transition would otherwise need a hand-maintained list in
    /// YAML of which validators had been ported: a second spelling of the
    /// registry, in a second language, updated by a different pull
    /// request than the one that ports the validator. It would go stale
    /// on the first class that forgot it, and a stale entry fails
    /// *silently* — the workflow would run `python3` against a script
    /// that had already been deleted, or run a Swift validator for a
    /// rule nobody had ported.
    ///
    /// Asking the registry instead means the port itself is the
    /// declaration: a class that adds its validator, with its
    /// `retiredScript`, is served by Swift from that moment, and every
    /// class that has not yet landed keeps running `python3`. That is
    /// what lets the classes merge independently and delete
    /// independently.
    ///
    /// Matching is exact on the recorded path. A validator whose
    /// counterpart is already deleted records `nil` and is therefore
    /// never selected this way — by then no caller names the script.
    public static func validator(replacing script: String) -> (any CI.Validation.Validator)? {
        validators.first { $0.retiredScript == script }
    }
}
