import Foundation

extension Rulebook {
    /// The prune-only ratchet: findings that are known, recorded, and not
    /// counted as new.
    ///
    /// Prune-only is the whole design. Entries may leave — that is a
    /// repair — and may not arrive, so the corpus can only get cleaner.
    /// A baseline that grew would be a list of things nobody intends to
    /// fix wearing the costume of a plan.
    ///
    /// One entry per line, `<check> <key>`; `#` comments and blank lines
    /// ignored.
    public struct Baseline: Sendable {
        public let entries: Set<String>

        public init(entries: Set<String>) { self.entries = entries }

        /// Read the baseline beside the corpus configuration, or an empty
        /// one when the file is absent — a missing baseline is a clean
        /// slate, not a defect.
        public static func read(at path: String) -> Self {
            guard let data = FileManager.default.contents(atPath: path) else {
                return Self(entries: [])
            }
            let lines = String(decoding: data, as: UTF8.self)
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return Self(entries: Set(lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }))
        }

        public func covers(_ finding: Finding) -> Bool {
            entries.contains(finding.baselineEntry)
        }
    }
}
