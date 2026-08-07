extension Fleet.Audit {
    /// The linter the γ-2 audit measures with, and the rule set it
    /// measures against.
    ///
    /// yamllint is a Python program and stays one — the audit's subject
    /// is other repositories' YAML, and swapping the instrument would
    /// move every package's baseline. What was Python here, and is no
    /// longer, is the *decision*: which rules, at which levels. Those
    /// are values now, and the config text below is generated from them
    /// rather than kept as a heredoc that could drift from the numbers
    /// the weekly sweep reports against.
    public enum Yamllint {
        /// Where the sweep writes the config, and where the audit reads
        /// it from. A single path, spelled once.
        public static let configurationPath = "/tmp/yamllint.yml"

        /// The canonical rule set. Byte-identical to the heredoc
        /// retired from `audit-setup-yamllint.py`; in particular
        /// `line-length: 200` and 2-space indentation, which the sweep's
        /// baseline numbers depend on.
        public static let configuration = """
            extends: default
            rules:
              document-start: disable
              line-length:
                max: 200
                level: warning
              truthy:
                allowed-values: ["true", "false"]
                check-keys: false
              indentation:
                spaces: 2
              comments:
                require-starting-space: false

            """

        /// The installation the sweep performs once per matrix job.
        public static let installation = ["python3", "-m", "pip", "install", "--quiet", "yamllint"]

        /// The audit's own invocation over a set of subjects.
        public static func invocation(subjects: [String]) -> [String] {
            ["yamllint", "-c", configurationPath] + subjects
        }
    }
}
