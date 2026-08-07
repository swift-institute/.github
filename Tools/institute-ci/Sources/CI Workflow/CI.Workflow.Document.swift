import CI_Contract

extension CI.Workflow {
    /// One GitHub Actions workflow file, read.
    ///
    /// This is the type the retired `validate_lib.py` expressed as three
    /// loose functions (`parse_on_block`, `iter_jobs`,
    /// `load_workflow_yaml_or_emit`). Rules consume `triggers` and
    /// `jobs`; nothing else needs to walk the raw node tree, and a rule
    /// that does should be read as a request to widen this type.
    public struct Document: Sendable, Equatable {
        /// The file's base name, as findings cite it.
        public let name: String

        /// The whole document. Present for rules the typed accessors do
        /// not yet serve; prefer the accessors.
        public let root: YAML.Node

        public init(name: String, text: String) throws(YAML.Error) {
            self.name = name
            self.root = try YAML.Parser.parse(text)
        }

        /// The top-level mapping, or `nil` when the document's root is
        /// not a mapping. The Python contract treated a non-mapping root
        /// as "nothing to check", and so does every rule here.
        public var body: YAML.Mapping? { root.mapping }

        /// The `on:` block in its map form, or `nil` for the bare-keyword
        /// (`on: push`), list (`on: [push]`), and absent shapes.
        ///
        /// The two-step lookup is the YAML 1.1 recovery: `on` is a
        /// *boolean* key under 1.1, so a string lookup misses and the
        /// boolean lookup finds it. A document that quotes the key
        /// (`"on":`) is found by the first step. Both spellings occur in
        /// the corpus.
        public var triggers: YAML.Mapping? {
            guard let body else { return nil }
            let node = body["on"] ?? body[node: .boolean(true)]
            return node?.mapping
        }

        /// Every well-formed job, in document order.
        ///
        /// Jobs whose value is not a mapping are skipped rather than
        /// reported — matching `iter_jobs`, whose skip-malformed
        /// behaviour several rules depend on.
        public var jobs: [Job] {
            guard let jobs = body?["jobs"]?.mapping else { return [] }
            return jobs.entries.compactMap { entry in
                guard let name = entry.key.text, let body = entry.value.mapping else { return nil }
                return Job(name: name, body: body)
            }
        }
    }
}
