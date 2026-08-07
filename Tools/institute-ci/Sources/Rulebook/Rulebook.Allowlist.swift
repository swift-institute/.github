import Foundation

extension Rulebook {
    /// Duplicate definition sites that are sanctioned mirrors per
    /// `[SKILL-CREATE-016]`.
    ///
    /// Distinct from the baseline, and deliberately so: a baseline entry
    /// says "this is wrong and not yet fixed", an allowlist entry says
    /// "this is right". Conflating them would let a real contradiction
    /// hide behind a repair backlog.
    ///
    /// One entry per line, `<ID> <root-alias:relative-path>`; the
    /// identifier may be written bracketed.
    public struct Allowlist: Sendable {
        public let entries: Set<Entry>

        public struct Entry: Sendable, Hashable {
            public let identifier: Identifier
            public let alias: String

            public init(identifier: Identifier, alias: String) {
                self.identifier = identifier
                self.alias = alias
            }
        }

        public init(entries: Set<Entry>) { self.entries = entries }

        public static func read(at path: String) -> Self {
            guard let data = FileManager.default.contents(atPath: path) else {
                return Self(entries: [])
            }
            var entries: Set<Entry> = []
            for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                guard let split = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                    continue
                }
                let identifier = String(trimmed[..<split])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let alias = String(trimmed[trimmed.index(after: split)...])
                    .trimmingCharacters(in: .whitespaces)
                guard !alias.isEmpty else { continue }
                entries.insert(Entry(identifier: .init(identifier), alias: alias))
            }
            return Self(entries: entries)
        }

        /// The aliases sanctioned to mirror an identifier.
        public func aliases(mirroring identifier: Identifier) -> Set<String> {
            Set(entries.filter { $0.identifier == identifier }.map(\.alias))
        }
    }
}
