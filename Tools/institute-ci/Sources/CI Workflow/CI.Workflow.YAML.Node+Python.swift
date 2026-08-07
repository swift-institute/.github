import CI_Contract

extension CI.Workflow.YAML.Node {
    /// The node as `str()` renders the object PyYAML loaded from it.
    ///
    /// The retired validators reach for `str(step.get("uses", ""))`
    /// before testing a prefix, and then quote the same value back into
    /// the finding. Reproducing the finding byte-for-byte therefore means
    /// reproducing Python's rendering, not Swift's — `True` rather than
    /// `true`, `None` rather than `nil`, `{'a': 1}` rather than any
    /// Swift description.
    ///
    /// A string renders as itself; everything else renders as its
    /// `repr`, which is what `str` does for every type here.
    public var pythonString: String {
        switch self {
        case .text(let value): value
        default: pythonRepr
        }
    }

    /// The node as `repr()` renders the object PyYAML loaded from it.
    ///
    /// Container elements render by `repr` even inside a `str`, which is
    /// why this is the recursive one and `pythonString` defers to it.
    public var pythonRepr: String {
        switch self {
        case .null: "None"
        case .boolean(let value): value ? "True" : "False"
        case .integer(let value): "\(value)"
        case .number(let value): "\(value)"
        case .text(let value): Self.repr(value)
        case .sequence(let elements):
            "[" + elements.map(\.pythonRepr).joined(separator: ", ") + "]"
        case .mapping(let mapping):
            "{"
                + mapping.entries
                .map { "\($0.key.pythonRepr): \($0.value.pythonRepr)" }
                .joined(separator: ", ") + "}"
        }
    }

    /// `repr()` of a Python string.
    ///
    /// Single quotes unless the value contains one and no double quote —
    /// Python's own rule, and the corpus contains both shapes because
    /// workflow values are quoted YAML.
    public static func repr(_ value: String) -> String {
        let quote: Character =
            value.contains("'") && !value.contains("\"") ? "\"" : "'"
        var result = String(quote)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += #"\\"#
            case "\n": result += #"\n"#
            case "\r": result += #"\r"#
            case "\t": result += #"\t"#
            case Unicode.Scalar(String(quote).unicodeScalars.first!):
                result += "\\\(quote)"
            case let scalar where scalar.value < 0x20 || scalar.value == 0x7F:
                result += "\\x" + Self.hexadecimal(scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        result.append(quote)
        return result
    }

    private static func hexadecimal(_ value: UInt32) -> String {
        let digits = "0123456789abcdef"
        let high = digits[digits.index(digits.startIndex, offsetBy: Int(value >> 4))]
        let low = digits[digits.index(digits.startIndex, offsetBy: Int(value & 0xF))]
        return "\(high)\(low)"
    }
}
