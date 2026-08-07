import CI_Contract

extension CI.Workflow.YAML {
    /// Renders a node as canonical JSON: key-sorted, no insignificant
    /// whitespace, one deterministic spelling per value.
    ///
    /// Two jobs, both about comparison rather than transport.
    ///
    /// First, it is how this reader is *proved*. Comparing a validator's
    /// findings only exercises the handful of keys that validator reads;
    /// comparing the canonical rendering of the whole document against
    /// the same document loaded by PyYAML exercises the reader itself —
    /// every scalar resolution, every nesting, every block scalar.
    ///
    /// Second, C7's verdict inventory is a JSON contract whose identity
    /// gate is canonical-JSON equality, and it should not grow a second
    /// serializer to get one.
    ///
    /// Mapping keys become strings, because JSON has no other kind. A
    /// boolean key — YAML 1.1's `on:` — renders as `"true"`, which is
    /// exactly what Python's `json.dumps` does with the same document.
    public enum Canonical {
        public static func json(_ node: Node) -> String {
            switch node {
            case .null:
                return "null"
            case .boolean(let value):
                return value ? "true" : "false"
            case .integer(let value):
                return String(value)
            case .number(let value):
                return String(value)
            case .text(let value):
                return quoted(value)
            case .sequence(let elements):
                return "[" + elements.map(json).joined(separator: ",") + "]"
            case .mapping(let mapping):
                let members = mapping.entries
                    .map { (key(from: $0.key), json($0.value)) }
                    .sorted { $0.0 < $1.0 }
                    .map { "\(quoted($0.0)):\($0.1)" }
                return "{" + members.joined(separator: ",") + "}"
            }
        }

        private static func key(from node: Node) -> String {
            switch node {
            case .text(let value): value
            case .boolean(let value): value ? "true" : "false"
            case .integer(let value): String(value)
            case .number(let value): String(value)
            case .null: "null"
            default: json(node)
            }
        }

        private static func quoted(_ value: String) -> String {
            var result = "\""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\"": result += "\\\""
                case "\\": result += "\\\\"
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                case let scalar where scalar.value < 0x20:
                    result += "\\u" + hexadecimal(scalar.value)
                case let scalar:
                    result.unicodeScalars.append(scalar)
                }
            }
            return result + "\""
        }

        private static func hexadecimal(_ value: UInt32) -> String {
            let digits = "0123456789abcdef"
            var result = ""
            for shift in stride(from: 12, through: 0, by: -4) {
                let nibble = Int((value >> UInt32(shift)) & 0xF)
                result.append(Array(digits)[nibble])
            }
            return result
        }
    }
}
