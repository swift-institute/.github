extension Closure.Evidence {
    /// What one body of comment text cites: Actions run URLs and
    /// commit-shaped hex tokens. Parsing is deliberately syntactic —
    /// whether a cited run is evidence is the verdict's question, not
    /// the parser's.
    public struct Citation: Sendable, Equatable {
        /// One cited `https://github.com/<owner>/<repo>/actions/runs/<id>`
        /// coordinate. Suffixes past the run id (job pages, `/attempts/N`)
        /// cite the same run and resolve to the same reference.
        public struct RunReference: Sendable, Equatable, Hashable {
            public let owner: String
            public let repository: String
            public let identifier: String

            public init(owner: String, repository: String, identifier: String) {
                self.owner = owner
                self.repository = repository
                self.identifier = identifier
            }

            public var url: String {
                "https://github.com/\(owner)/\(repository)/actions/runs/\(identifier)"
            }
        }

        public let runs: [RunReference]
        /// Cited fix-commit SHAs: full 40-hex tokens plus abbreviated
        /// 7–39-hex tokens. Ordinary English words are excluded by the
        /// digit requirement below.
        public let commits: [String]

        public init(runs: [RunReference], commits: [String]) {
            self.runs = runs
            self.commits = commits
        }

        /// Parse one comment body.
        public init(of body: String) {
            var runs: [RunReference] = []
            var commits: [String] = []

            let punctuation: Set<Character> = ["`", ".", ",", ";", ":", "!", "?", "<", ">", "[", "]", "\"", "'"]
            for rawWord in body.split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ")" }) {
                let word = String(
                    rawWord.drop(while: { punctuation.contains($0) })
                        .reversed().drop(while: { punctuation.contains($0) }).reversed())
                if let reference = Citation.runReference(of: word) {
                    if !runs.contains(reference) { runs.append(reference) }
                    continue
                }
                if Citation.isCommitToken(word) {
                    let lowered = word.lowercased()
                    if !commits.contains(lowered) { commits.append(lowered) }
                }
            }
            self.init(runs: runs, commits: commits)
        }

        static func runReference(of word: String) -> RunReference? {
            let prefix = "https://github.com/"
            guard word.hasPrefix(prefix) else { return nil }
            let parts = word.dropFirst(prefix.count).split(separator: "/")
            guard parts.count >= 4,
                  parts[2] == "actions", parts[3] == "runs",
                  parts.count >= 5
            else { return nil }
            let identifier = parts[4].prefix(while: \.isNumber)
            guard !identifier.isEmpty else { return nil }
            return RunReference(
                owner: String(parts[0]), repository: String(parts[1]),
                identifier: String(identifier))
        }

        static func isCommitToken(_ word: String) -> Bool {
            guard word.count >= 7, word.count <= 40 else { return false }
            guard word.allSatisfy(\.isHexDigit) else { return false }
            // Require at least one decimal digit: an all-letter hex word
            // ("deadbee" aside, "decades" is not hex; but "accedes" is)
            // is far more often English than a commit.
            return word.contains(where: \.isNumber)
        }
    }
}
