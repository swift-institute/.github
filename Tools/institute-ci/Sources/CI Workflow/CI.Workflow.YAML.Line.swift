import CI_Contract

extension CI.Workflow.YAML {
    /// One physical line, pre-measured for the indentation-driven parse.
    ///
    /// Comment removal happens here rather than in a whole-text
    /// pre-pass, because inside a literal block scalar a `#` is content.
    /// `raw` therefore stays untouched and `content` carries the
    /// comment-stripped form; block scalars read `raw`, structure reads
    /// `content`.
    public struct Line: Sendable, Equatable {
        public let number: Int
        public let indent: Int
        public let raw: String
        public let content: String

        /// The line carries no characters at all (blank, or whitespace).
        public var isEmpty: Bool { raw.trimmedTrailing().isEmpty }

        /// Blank or comment-only: invisible to block structure.
        public var isSkippable: Bool { content.isEmpty }

        public var isSequenceItem: Bool { content == "-" || content.hasPrefix("- ") }

        /// The text following `- `, empty when the item's node is a block
        /// on the following lines.
        public var sequenceItemContent: String {
            guard isSequenceItem else { return "" }
            return String(content.dropFirst(1)).drop(while: { $0 == " " }).description
        }

        static func scan(_ text: String) -> [Self] {
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { offset, raw in
                    let raw = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
                    return Self(
                        number: offset + 1,
                        indent: raw.prefix(while: { $0 == " " }).count,
                        raw: raw,
                        content: stripComment(raw).trimmedTrailing()
                            .drop(while: { $0 == " " }).description)
                }
        }

        /// Remove a trailing comment. A `#` opens a comment only at the
        /// start of the content or after whitespace, and never inside a
        /// quoted scalar.
        static func stripComment(_ raw: String) -> String {
            var quote: Character?
            var previous: Character = " "
            var result = ""
            for character in raw {
                if let open = quote {
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#", previous == " " || result.isEmpty {
                    break
                }
                result.append(character)
                previous = character
            }
            return result
        }

        /// Split `key: value` at the colon that terminates the key.
        ///
        /// Returns `nil` when the line is a plain scalar rather than a
        /// mapping entry. The colon must be followed by a space or end
        /// the line, and must sit outside quotes and outside a flow
        /// collection — otherwise `uses: org/repo@main` and
        /// `[a, b]` would split in the wrong place.
        static func splitKey(_ content: String) -> (key: String, value: String)? {
            var quote: Character?
            var depth = 0
            let characters = Array(content)
            for index in characters.indices {
                let character = characters[index]
                if let open = quote {
                    if character == open { quote = nil }
                    continue
                }
                switch character {
                case "\"", "'": quote = character
                case "[", "{": depth += 1
                case "]", "}": depth -= 1
                case ":" where depth == 0:
                    let next = index + 1
                    guard next == characters.count || characters[next] == " " else { continue }
                    let key = String(characters[..<index]).trimmedTrailing()
                    guard !key.isEmpty else { return nil }
                    let value = String(characters[next...]).drop(while: { $0 == " " })
                    return (key, value.description.trimmedTrailing())
                default: continue
                }
            }
            return nil
        }

        /// Undo quoting, or return `nil` when the scalar is plain.
        static func unquote(_ text: String) -> String? {
            guard text.count >= 2, let first = text.first, text.hasSuffix(String(first)) else {
                return nil
            }
            let body = String(text.dropFirst().dropLast())
            switch first {
            case "'":
                var result = ""
                var index = body.startIndex
                while index < body.endIndex {
                    let next = body.index(after: index)
                    if body[index] == "'", next < body.endIndex, body[next] == "'" {
                        result.append("'")
                        index = body.index(after: next)
                    } else {
                        result.append(body[index])
                        index = next
                    }
                }
                return result
            case "\"":
                var result = ""
                var escaped = false
                for character in body {
                    if escaped {
                        switch character {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        case "r": result.append("\r")
                        case "0": result.append("\0")
                        default: result.append(character)
                        }
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else {
                        result.append(character)
                    }
                }
                return result
            default:
                return nil
            }
        }
    }
}

extension String {
    fileprivate func trimmedTrailing() -> String {
        var result = Substring(self)
        while let last = result.last, last == " " || last == "\t" { result = result.dropLast() }
        return String(result)
    }
}
