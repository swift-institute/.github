import CI_Contract

extension CI.Workflow.YAML {
    /// Reader for a single-line flow collection — `[main]`,
    /// `{ fetch-depth: 0 }`, and their nestings.
    ///
    /// Flow collections in workflow documents are always written on one
    /// line (`branches: [main]`, `paths: ['**.swift']`), so this reader
    /// deliberately does not span lines. A multi-line flow collection is
    /// reported as unsupported rather than mis-read.
    struct Flow {
        private let characters: [Character]
        private var index: Int = 0

        init(_ text: String) {
            self.characters = Array(text)
        }

        mutating func parse(on line: Int) throws(Error) -> Node {
            let node = try value(on: line)
            skipSpaces()
            guard index == characters.count else {
                throw Error.unsupported(line: line, construct: "trailing text after a flow collection")
            }
            return node
        }

        private mutating func value(on line: Int) throws(Error) -> Node {
            skipSpaces()
            guard index < characters.count else {
                throw Error.unsupported(line: line, construct: "an empty flow value")
            }
            switch characters[index] {
            case "[": return try sequence(on: line)
            case "{": return try mapping(on: line)
            default: return scalar()
            }
        }

        private mutating func sequence(on line: Int) throws(Error) -> Node {
            index += 1
            var elements: [Node] = []
            skipSpaces()
            if peek() == "]" { index += 1; return .sequence(elements) }
            while true {
                elements.append(try value(on: line))
                skipSpaces()
                switch peek() {
                case ",": index += 1
                case "]": index += 1; return .sequence(elements)
                default:
                    throw Error.unsupported(line: line, construct: "an unterminated flow sequence")
                }
            }
        }

        private mutating func mapping(on line: Int) throws(Error) -> Node {
            index += 1
            var entries: [Mapping.Entry] = []
            skipSpaces()
            if peek() == "}" { index += 1; return .mapping(Mapping(entries)) }
            while true {
                let key = try value(on: line)
                skipSpaces()
                guard peek() == ":" else {
                    throw Error.unsupported(line: line, construct: "a flow mapping entry without a value")
                }
                index += 1
                entries.append((key, try value(on: line)))
                skipSpaces()
                switch peek() {
                case ",": index += 1
                case "}": index += 1; return .mapping(Mapping(entries))
                default:
                    throw Error.unsupported(line: line, construct: "an unterminated flow mapping")
                }
            }
        }

        /// A flow scalar runs to the next structural character.
        private mutating func scalar() -> Node {
            if let quote = peek(), quote == "\"" || quote == "'" {
                let start = index
                index += 1
                while index < characters.count {
                    defer { index += 1 }
                    if characters[index] == quote { break }
                }
                let text = String(characters[start..<index])
                return .text(Line.unquote(text) ?? text)
            }
            let start = index
            while index < characters.count, !",[]{}:".contains(characters[index]) { index += 1 }
            var text = String(characters[start..<index])
            while text.hasSuffix(" ") { text.removeLast() }
            return Resolver.resolve(text)
        }

        private func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " { index += 1 }
        }
    }
}
