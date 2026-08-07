import CI_Contract

extension CI.Workflow {
    /// A deliberately bounded YAML reader for GitHub Actions workflow
    /// documents.
    ///
    /// This is **not** a general YAML implementation and must not be
    /// presented as one. It covers exactly the constructs the Actions
    /// document surface uses — block mappings, block sequences, flow
    /// sequences and mappings, single/double quoted scalars, literal and
    /// folded block scalars, and comments — and it resolves plain scalars
    /// under **YAML 1.1** rules rather than 1.2.
    ///
    /// The 1.1 choice is load-bearing, not incidental. The retired Python
    /// validators read these documents through PyYAML, whose resolver is
    /// 1.1: the key `on:` resolves to the boolean `true`, not to the
    /// string `"on"`, and `yes`/`no`/`off` are booleans. Every workflow in
    /// the fixture corpus exercises that quirk on its very first key. A
    /// 1.2 reader would silently disagree with the corpus, so the
    /// resolution rules are reproduced here on purpose.
    ///
    /// The long-term owner of a general YAML reader is a Standards-layer
    /// package (there is none in the ecosystem today). When one exists,
    /// this type is the seam to retire — but only behind a reader that
    /// can still express 1.1 resolution.
    public enum YAML {}
}
