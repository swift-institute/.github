import CI_Contract

extension CI.Workflow.YAML {
    /// Plain-scalar resolution under **YAML 1.1**, matching PyYAML's
    /// implicit resolver — the reader every retired validator used.
    ///
    /// The differences from 1.2 that matter to the workflow corpus:
    ///
    /// - `on`, `off`, `yes`, `no` (and their capitalised and upper-case
    ///   spellings) are booleans. This is why `on:` is a boolean key.
    /// - Integers accept `_` digit separators and a leading `0` octal
    ///   form.
    ///
    /// Quoted scalars never reach this type: quoting suppresses implicit
    /// resolution in both versions, so `"on"` stays a string.
    public enum Resolver {
        /// Resolve one plain scalar's text to a node.
        public static func resolve(_ text: String) -> Node {
            if text.isEmpty { return .null }
            if isNull(text) { return .null }
            if let value = boolean(text) { return .boolean(value) }
            if let value = integer(text) { return .integer(value) }
            if let value = number(text) { return .number(value) }
            return .text(text)
        }

        private static func isNull(_ text: String) -> Bool {
            switch text {
            case "~", "null", "Null", "NULL": true
            default: false
            }
        }

        // PyYAML's bool resolver, spelled out rather than lower-cased,
        // because 1.1 accepts only these spellings — `yEs` is a string.
        private static func boolean(_ text: String) -> Bool? {
            switch text {
            case "yes", "Yes", "YES", "true", "True", "TRUE", "on", "On", "ON": true
            case "no", "No", "NO", "false", "False", "FALSE", "off", "Off", "OFF": false
            default: nil
            }
        }

        private static func integer(_ text: String) -> Int? {
            var body = Substring(text)
            var negative = false
            if body.first == "+" { body = body.dropFirst() } else if body.first == "-" {
                negative = true
                body = body.dropFirst()
            }
            guard !body.isEmpty else { return nil }
            let digits = String(body.filter { $0 != "_" })
            guard !digits.isEmpty else { return nil }

            let magnitude: Int?
            if digits.hasPrefix("0b") || digits.hasPrefix("0B") {
                magnitude = Int(digits.dropFirst(2), radix: 2)
            } else if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
                magnitude = Int(digits.dropFirst(2), radix: 16)
            } else if digits.hasPrefix("0o") {
                magnitude = Int(digits.dropFirst(2), radix: 8)
            } else if digits.count > 1, digits.hasPrefix("0") {
                magnitude = Int(digits.dropFirst(), radix: 8)
            } else {
                guard digits.allSatisfy({ $0.isNumber }) else { return nil }
                magnitude = Int(digits, radix: 10)
            }
            guard let magnitude else { return nil }
            return negative ? -magnitude : magnitude
        }

        private static func number(_ text: String) -> Double? {
            switch text {
            case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": return .infinity
            case "-.inf", "-.Inf", "-.INF": return -.infinity
            case ".nan", ".NaN", ".NAN": return .nan
            default: break
            }
            // Require a decimal point or exponent so a bare word never
            // resolves numerically.
            guard text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) else { return nil }
            guard text.allSatisfy({ $0.isNumber || "+-._eE".contains($0) }) else { return nil }
            return Double(String(text.filter { $0 != "_" }))
        }
    }
}
