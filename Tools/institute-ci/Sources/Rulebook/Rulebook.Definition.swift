extension Rulebook {
    /// Where an identifier is defined.
    ///
    /// Two sanctioned forms, and the distinction between them decides
    /// what counts as a duplicate:
    ///
    /// - **heading** — `### [ID]`, level 2 or deeper. The canonical form,
    ///   and the only one the duplicate check counts. Two headings for
    ///   one identifier is a contradiction waiting to happen.
    /// - **registry** — a row or sub-label enumerated by the file's
    ///   **Rules in this file** header. This is an *index* of what the
    ///   file defines, so a registry entry naming a heading in the same
    ///   file is not a second definition, and counting it as one would
    ///   fail every catalogue-form skill.
    public struct Definition: Sendable, Equatable {
        public enum Form: Sendable, Equatable {
            case heading
            case registry
        }

        public let alias: String
        /// The 1-based line for a heading; `0` for a registry claim,
        /// which is a claim of the file rather than of a line.
        public let line: Int
        public let form: Form

        public init(alias: String, line: Int, form: Form) {
            self.alias = alias
            self.line = line
            self.form = form
        }
    }
}
