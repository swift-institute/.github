import CI_Contract

// Nest.Name namespace shell (FT1-ratification.json;
// naming-annex-nest-name.md). `CI.Canon` owns the *documents this control
// plane distributes* — files whose authoritative text lives in
// `swift-institute/.github` and is propagated into every package.
//
// It sits below `CI.Validation` on purpose. A canonical document has two
// consumers that must never disagree: the sweep that *renders* it into a
// repository (`sync-gitignore.yml`) and the gate that *checks* it there
// (`validate-gitignore.yml`). While those were two Python scripts —
// `render-gitignore.py` and `validate-gitignore.py` — each carried its own
// copy of the section-marker arithmetic, and a canon edit had to be
// mirrored in both. One owner, two consumers.
extension CI {
    public enum Canon {}
}
