import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// Rendering that exists only because the retired Python corpus
    /// rendered it.
    ///
    /// Several ported messages interpolate a value the retired script
    /// interpolated with `!r`, or a sorted collection Python printed as a
    /// `list` literal. Those spellings are load-bearing: the port's one
    /// unwaived gate is byte-identity of the sorted TSV against the
    /// retired implementation, so `['push', 'pull_request']` and
    /// `'.github/scripts/validate-foo.py'` are part of the finding, not
    /// incidental formatting.
    ///
    /// Kept in one named place, and named for what it is, so that when
    /// the retired scripts are gone a reader can see at a glance which
    /// message text is inherited rather than chosen — and can change it
    /// deliberately rather than discover the constraint by breaking a
    /// differential run.
    ///
    /// This is a compatibility surface with a scheduled end: once the
    /// last Python counterpart is deleted and the messages are free to be
    /// rewritten in the Institute's own voice, it goes with them.
    public enum Retired {
        /// A string as Python's `repr` writes it — single-quoted, with
        /// backslashes and single quotes escaped, and a double-quoted
        /// form when the value contains a single quote but no double
        /// quote.
        public static func quoted(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\r", with: "\\r")
            if escaped.contains("'") && !escaped.contains("\"") {
                return "\"\(escaped)\""
            }
            return "'\(escaped.replacingOccurrences(of: "'", with: "\\'"))'"
        }

        /// A collection as Python prints a `list` of strings:
        /// `['a', 'b']`.
        public static func list(_ values: [String]) -> String {
            "[\(values.map(quoted).joined(separator: ", "))]"
        }

        /// A parsed YAML value as `repr` writes it.
        ///
        /// Only the scalar shapes the manifest schema admits are spelled
        /// out; a mapping or a sequence in a scalar position is already a
        /// schema violation the caller reports differently.
        public static func value(_ node: CI.Workflow.YAML.Node) -> String {
            switch node {
            case .null: "None"
            case .boolean(let value): value ? "True" : "False"
            case .integer(let value): "\(value)"
            case .number(let value): "\(value)"
            case .text(let value): quoted(value)
            case .sequence(let value): "[\(value.map(self.value).joined(separator: ", "))]"
            case .mapping: "{...}"
            }
        }

        /// The Python type name `type(x).__name__` reports for a parsed
        /// YAML value.
        public static func typeName(_ node: CI.Workflow.YAML.Node) -> String {
            switch node {
            case .null: "NoneType"
            case .boolean: "bool"
            case .integer: "int"
            case .number: "float"
            case .text: "str"
            case .sequence: "list"
            case .mapping: "dict"
            }
        }

        /// Whether Python's `if value:` would take the branch.
        ///
        /// The retired checks spell emptiness as truthiness, so an absent
        /// key, an explicit `null`, and `''` are one case and must stay
        /// one case.
        public static func isTruthy(_ node: CI.Workflow.YAML.Node) -> Bool {
            switch node {
            case .null: false
            case .boolean(let value): value
            case .integer(let value): value != 0
            case .number(let value): value != 0
            case .text(let value): !value.isEmpty
            case .sequence(let value): !value.isEmpty
            case .mapping(let value): !value.entries.isEmpty
            }
        }
    }
}
