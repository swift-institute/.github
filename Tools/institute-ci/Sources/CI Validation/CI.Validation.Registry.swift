import CI_Contract

extension CI.Validation {
    /// Rule identifier → validator.
    ///
    /// The Swift owner of what `tests/run.sh` held as two parallel `case`
    /// statements — `validator_for` and `prefix_for` — which could and
    /// did disagree. Here a validator declares its own rules and the
    /// index is derived, so a rule cannot be registered against one
    /// spelling and reported under another.
    ///
    /// **Wave-1 peers: this is the one shared file in the port.** Adding
    /// a validator means adding one line to `validators` and nothing
    /// else. Keep the list sorted by type name to make the conflict
    /// resolution mechanical.
    public enum Registry {
        public static let validators: [any Validator] = [
            BinaryInstallChecksum(),
            BranchPins(),
            CompositeActionPins(),
            ContinueOnError(),
            Drift.LintValidatorsWeekly(),
            Drift.ScheduledWorkflowAlert(),
            Gitignore(),
            ManifestBinding(),
            VisibilityGate(),
        ]

        /// The validator authoritative for a rule, or `nil` when the rule
        /// has no Swift owner yet.
        public static func validator(for rule: Rule) -> (any Validator)? {
            validators.first { $0.rules.contains(rule) }
        }

        /// Every registered rule, sorted.
        public static var rules: [Rule] {
            validators.flatMap(\.rules).sorted()
        }

        /// The rule a fixture-corpus directory names.
        ///
        /// The corpus spells identifiers in lower case (`ci-105`,
        /// `plat-arch-008c`) while findings cite the registered spelling
        /// (`CI-105`, `PLAT-ARCH-008c`). Case-insensitive matching against
        /// the registry replaces the hand-maintained `prefix_for` table,
        /// so the two spellings cannot drift apart.
        public static func rule(forCorpusDirectory directory: String) -> Rule? {
            rules.first { $0.rawValue.lowercased() == directory.lowercased() }
        }
    }
}
