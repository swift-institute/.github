extension Repository.Policy {
    /// A repository's declarative editorial state — the document that
    /// lives at `.github/metadata.yaml` and that `sync-metadata` reads
    /// and propagates to GitHub.
    ///
    /// Per the Wave 2b Decision 6 pivot (2026-05-10) the YAML is the
    /// source of truth: description, topics, and homepage are authored
    /// there and never re-derived in the steady state. This type is that
    /// document's three propagated fields, and nothing else — the schema
    /// carries further blocks (`settings`, `sidebar`, `discussion`,
    /// `socialPreview`, `readme`) that no Swift consumer reads yet, and
    /// modelling fields nobody consumes is how a type starts drifting
    /// from the schema that defines it.
    public struct Metadata: Sendable, Equatable {
        public let description: String
        public let topics: [String]
        /// Empty means *omit the key*, which is not the same as an empty
        /// homepage: an org `.github` repository has no website, and the
        /// draft must not assert one.
        public let homepage: String

        public init(description: String, topics: [String], homepage: String) {
            self.description = description
            self.topics = topics
            self.homepage = homepage
        }
    }
}
