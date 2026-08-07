extension Rulebook {
    /// The four things the rulebook checks about itself.
    ///
    /// All four are *referential*: they ask whether the corpus's internal
    /// pointers still land, never whether a rule is a good rule. Findings
    /// are reported in this declaration order, which is the order the
    /// retired engine printed them and the order a reader fixes them in —
    /// a dangling citation is usually the symptom of a duplicate or a
    /// moved file above it.
    public enum Check: String, Sendable, CaseIterable {
        /// Every `[ID]` cite resolves to a definition.
        case citations
        /// One canonical definition site per identifier, mirrors
        /// allowlisted.
        case duplicates
        /// Every cited workspace path exists, or the line is
        /// aspirational-tensed.
        case artifacts
        /// Companions named from their hub; registry claims traceable in
        /// their own file.
        case hubIndex = "hub-index"
    }
}
