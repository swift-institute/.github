import Foundation

extension Rulebook {
    /// One markdown file of the corpus, split the way the checks read
    /// it.
    ///
    /// Two splits, both load-bearing:
    ///
    /// - **frontmatter from body.** Frontmatter carries changelog history
    ///   lines that cite retired identifiers on purpose; scanning them
    ///   would report the corpus's own memory as rot.
    /// - **fenced code from prose.** A citation inside a fenced example
    ///   is illustration, not a claim, so the citation, duplicate, and
    ///   hub checks read prose only. Artifact existence deliberately
    ///   reads *everything*: a stale path in a copy-pasteable command is
    ///   worse than one in a sentence, not better.
    ///
    /// The fence line itself is marked as code, which is why a fence
    /// never reads as a definition or a citation site.
    public struct Document: Sendable {
        /// One body line: its 1-based number, its text, and whether it
        /// sits inside a fenced block.
        public struct Line: Sendable, Equatable {
            public let number: Int
            public let text: String
            public let isCode: Bool
        }

        /// The path on disk.
        public let path: String

        /// How the corpus names this file — `institute:architecture/SKILL.md`.
        /// Root-relative and root-labelled, so a finding reads the same
        /// on any machine.
        public let alias: String

        public let frontmatter: [String]
        public let body: [Line]

        public init(path: String, alias: String, text: String) {
            self.path = path
            self.alias = alias
            let lines = text.components(separatedBy: "\n").dropLastIfEmpty()
            var end = 0
            if lines.first?.trimmed == "---" {
                for index in 1..<max(lines.count, 1) where lines[index].trimmed == "---" {
                    end = index + 1
                    break
                }
            }
            self.frontmatter = Array(lines[..<end])
            var body: [Line] = []
            var inCode = false
            for index in end..<lines.count {
                let text = lines[index]
                let trimmedLeading = text.drop(while: { $0 == " " || $0 == "\t" })
                if trimmedLeading.hasPrefix("```") || trimmedLeading.hasPrefix("~~~") {
                    body.append(Line(number: index + 1, text: text, isCode: true))
                    inCode.toggle()
                    continue
                }
                body.append(Line(number: index + 1, text: text, isCode: inCode))
            }
            self.body = body
        }

        /// The file's name, without its directory.
        public var name: String { (path as NSString).lastPathComponent }

        /// The directory the file sits in.
        public var directory: String { (path as NSString).deletingLastPathComponent }

        /// Body lines outside fenced blocks — what a claim can be made
        /// on.
        public var prose: [Line] { body.filter { !$0.isCode } }

        /// The identifier a line defines by heading form, or `nil`.
        ///
        /// Level 2 and deeper, per `[AUDIT-028]b`; a level-1 heading is
        /// the document's own title.
        public static func headingDefinition(on line: String) -> Identifier? {
            var rest = Substring(line)
            var hashes = 0
            while rest.first == "#" {
                hashes += 1
                rest = rest.dropFirst()
            }
            guard (2...6).contains(hashes), let first = rest.first, first == " " || first == "\t"
            else { return nil }
            rest = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard rest.first == "[", let close = rest.firstIndex(of: "]") else { return nil }
            let inner = String(rest[rest.index(after: rest.startIndex)..<close])
            guard Identifier.isNumeric(inner) || Identifier.isWord(inner) else { return nil }
            return Identifier(inner)
        }

        /// Whether the line opens a **Rules in this file** registry — the
        /// header whose enumeration is itself a definition claim.
        public static func isRegistryHeader(_ line: String) -> Bool {
            let lowered = line.lowercased()
            return lowered.hasPrefix("**rules in this file**")
                || lowered.hasPrefix("**rules in this file:**")
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

extension Array where Element == String {
    /// Drops the empty trailing element `components(separatedBy:)`
    /// produces for a text ending in a newline, matching Python's
    /// `splitlines()`.
    fileprivate func dropLastIfEmpty() -> [String] {
        last == "" ? Array(dropLast()) : self
    }
}
