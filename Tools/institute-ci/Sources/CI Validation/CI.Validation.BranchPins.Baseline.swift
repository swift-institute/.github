import CI_Contract
import Foundation

extension CI.Validation.BranchPins {
    /// The shrink-only burn-down ledger of already-known branch pins.
    ///
    /// A `(repository, dependency URL)` pair in the ledger reports as
    /// `BRANCH-PIN-BASELINE` — informational, never a failure — while
    /// every other pin reports as `BRANCH-PIN-001`. The pair is the key,
    /// not the URL: the same dependency pinned by a *different*
    /// repository is a new pin and must still fire. That near-miss is
    /// one of the retired suite's controls, and it is kept here.
    ///
    /// A missing file is an empty ledger, not a defect. The ledger is an
    /// optional suppression list; its absence means nothing is
    /// suppressed, which fails closed.
    public struct Baseline: Sendable, Equatable {
        /// One suppressed declaration.
        public struct Entry: Sendable, Hashable {
            public let repository: String
            public let url: String

            public init(repository: String, url: String) {
                self.repository = repository
                self.url = url
            }
        }

        public static let empty = Self(entries: [])

        public let entries: Set<Entry>

        public init(entries: Set<Entry>) {
            self.entries = entries
        }

        public func suppresses(repository: String, url: String) -> Bool {
            entries.contains(Entry(repository: repository, url: url))
        }

        /// Read the ledger at `path`; a missing file is `.empty`.
        ///
        /// Lines are `repository<TAB>url`. Blank lines and `#` comments
        /// are ignored, and a line that does not split into exactly two
        /// tab-separated fields is ignored rather than guessed at — a
        /// malformed ledger line must not silently suppress something
        /// adjacent to what it names.
        public static func read(
            at path: String?
        ) throws(CI.Validation.EnvironmentDefect) -> Self {
            guard let path, FileManager.default.fileExists(atPath: path) else { return .empty }
            guard let data = FileManager.default.contents(atPath: path) else {
                throw .unreadableFile(path: path)
            }
            var entries: Set<Entry> = []
            for line in String(decoding: data, as: UTF8.self).split(
                separator: "\n",
                omittingEmptySubsequences: false
            ) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let fields = trimmed.components(separatedBy: "\t")
                guard fields.count == 2 else { continue }
                entries.insert(Entry(repository: fields[0], url: fields[1]))
            }
            return Self(entries: entries)
        }
    }
}
