import CI_Contract
import CI_Workflow

extension CI.Validation.GitHubMetadata.Schema {
    /// A minimal JSON reader producing `CI.Workflow.YAML.Node`, for the
    /// schema document.
    ///
    /// Two properties the platform's own readers do not offer together
    /// motivate it: **key order** (a `Dictionary` would make keyword and
    /// property evaluation order non-deterministic, and Python's `dict`
    /// preserved it) and **scalar typing** (a `true` must stay a boolean
    /// and a `2` an integer without Darwin-only `CFGetTypeID`-style
    /// inspection). The instance side already lives in `Node`; parsing
    /// the schema into the same shape gives the messages one `repr`.
    public enum JSON {
        /// The document as a node, or `nil` when it is not JSON.
        public static func parse(_ text: String) -> CI.Workflow.YAML.Node? {
            var reader = Reader(text)
            guard let value = reader.value() else { return nil }
            reader.skipWhitespace()
            return reader.isAtEnd ? value : nil
        }

        private struct Reader {
            let scalars: [Unicode.Scalar]
            var cursor = 0

            init(_ text: String) {
                self.scalars = Array(text.unicodeScalars)
            }

            var isAtEnd: Bool { cursor >= scalars.count }

            mutating func skipWhitespace() {
                while !isAtEnd,
                    scalars[cursor] == " " || scalars[cursor] == "\t"
                        || scalars[cursor] == "\n" || scalars[cursor] == "\r"
                { cursor += 1 }
            }

            mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
                skipWhitespace()
                guard !isAtEnd, scalars[cursor] == scalar else { return false }
                cursor += 1
                return true
            }

            mutating func consume(literal: String) -> Bool {
                let literal = Array(literal.unicodeScalars)
                guard cursor + literal.count <= scalars.count,
                    Array(scalars[cursor..<cursor + literal.count]) == literal
                else { return false }
                cursor += literal.count
                return true
            }

            mutating func value() -> CI.Workflow.YAML.Node? {
                skipWhitespace()
                guard !isAtEnd else { return nil }
                switch scalars[cursor] {
                case "{": return object()
                case "[": return array()
                case "\"": return string().map { .text($0) }
                case "t": return consume(literal: "true") ? .boolean(true) : nil
                case "f": return consume(literal: "false") ? .boolean(false) : nil
                case "n": return consume(literal: "null") ? .null : nil
                default: return number()
                }
            }

            mutating func object() -> CI.Workflow.YAML.Node? {
                guard consume("{") else { return nil }
                var entries: [CI.Workflow.YAML.Mapping.Entry] = []
                if consume("}") { return .mapping(.init(entries)) }
                repeat {
                    skipWhitespace()
                    guard let key = string(), consume(":"), let value = value()
                    else { return nil }
                    entries.append((key: .text(key), value: value))
                } while consume(",")
                guard consume("}") else { return nil }
                return .mapping(.init(entries))
            }

            mutating func array() -> CI.Workflow.YAML.Node? {
                guard consume("[") else { return nil }
                var elements: [CI.Workflow.YAML.Node] = []
                if consume("]") { return .sequence(elements) }
                repeat {
                    guard let element = value() else { return nil }
                    elements.append(element)
                } while consume(",")
                guard consume("]") else { return nil }
                return .sequence(elements)
            }

            mutating func string() -> String? {
                guard consume("\"") else { return nil }
                var result = String.UnicodeScalarView()
                while !isAtEnd {
                    let scalar = scalars[cursor]
                    cursor += 1
                    switch scalar {
                    case "\"": return String(result)
                    case "\\":
                        guard !isAtEnd else { return nil }
                        let escape = scalars[cursor]
                        cursor += 1
                        switch escape {
                        case "\"", "\\", "/": result.append(escape)
                        case "b": result.append("\u{08}")
                        case "f": result.append("\u{0C}")
                        case "n": result.append("\n")
                        case "r": result.append("\r")
                        case "t": result.append("\t")
                        case "u":
                            guard let unit = hexUnit() else { return nil }
                            if (0xD800...0xDBFF).contains(unit) {
                                // A surrogate pair; the low half must follow.
                                guard consume(literal: "\\u"), let low = hexUnit(),
                                    (0xDC00...0xDFFF).contains(low),
                                    let paired = Unicode.Scalar(
                                        0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
                                else { return nil }
                                result.append(paired)
                            } else if let single = Unicode.Scalar(unit) {
                                result.append(single)
                            } else {
                                return nil
                            }
                        default: return nil
                        }
                    default:
                        result.append(scalar)
                    }
                }
                return nil
            }

            mutating func hexUnit() -> UInt32? {
                guard cursor + 4 <= scalars.count,
                    let unit = UInt32(
                        String(String.UnicodeScalarView(scalars[cursor..<cursor + 4])),
                        radix: 16)
                else { return nil }
                cursor += 4
                return unit
            }

            mutating func number() -> CI.Workflow.YAML.Node? {
                let start = cursor
                var isIntegral = true
                if !isAtEnd, scalars[cursor] == "-" { cursor += 1 }
                while !isAtEnd {
                    let scalar = scalars[cursor]
                    if ("0"..."9").contains(scalar) {
                        cursor += 1
                    } else if scalar == "." || scalar == "e" || scalar == "E"
                        || scalar == "+" || scalar == "-"
                    {
                        isIntegral = false
                        cursor += 1
                    } else {
                        break
                    }
                }
                let text = String(String.UnicodeScalarView(scalars[start..<cursor]))
                if isIntegral, let integer = Int(text) { return .integer(integer) }
                return Double(text).map { .number($0) }
            }
        }
    }
}
