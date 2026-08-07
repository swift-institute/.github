extension Fleet.Audit {
    /// The γ-2 mechanical-hygiene audit: consolidated yamllint scan plus
    /// broken-symlink scan over one package clone.
    ///
    /// The two counters are decided here, over an already-collected
    /// yamllint transcript and an already-walked symlink listing. Neither
    /// the linter run nor the walk is a decision, so neither is here.
    public enum MechanicalHygiene {
        /// The `yaml_issues` counter name.
        public static let yamlIssues = "yaml_issues"
        /// The `broken_links` counter name.
        public static let brokenLinks = "broken_links"

        /// A yamllint subject, relative to the package root.
        public struct Subject: Sendable, Equatable {
            public let path: String
            public let isDirectory: Bool

            public init(path: String, isDirectory: Bool) {
                self.path = path
                self.isDirectory = isDirectory
            }
        }

        /// The scan scope, per Research §3.4.5. `.swiftlint.yml` and
        /// `.swift-format` are deliberately outside it: [CI-057] leaves
        /// those to per-package autonomy, so a sweep that counted them
        /// would be reporting a package's own choice as a defect.
        public static let subjects: [Subject] = [
            Subject(path: ".github/workflows", isDirectory: true),
            Subject(path: ".github/dependabot.yml", isDirectory: false),
            Subject(path: ".github/metadata.yaml", isDirectory: false),
            Subject(path: "metadata.yaml", isDirectory: false),
        ]

        /// The subjects that exist in this clone, in declaration order.
        public static func present(
            in root: String, exists: (String, Bool) -> Bool
        ) -> [String] {
            subjects.compactMap { subject in
                let path = root + "/" + subject.path
                return exists(path, subject.isDirectory) ? path : nil
            }
        }

        /// Count yamllint diagnostics in a transcript.
        ///
        /// A diagnostic line is indented and opens with `line:column`.
        /// The shape is the counter — it is what the inline shell
        /// snippet this audit replaced counted, and the weekly sweep's
        /// baseline numbers are numbers of *this* shape, so widening it
        /// would read as a regression across every package at once.
        public static func yamlIssueCount(inTranscript transcript: String) -> Int {
            var count = 0
            for line in transcript.split(separator: "\n", omittingEmptySubsequences: false) {
                let body = line.drop { $0 == " " || $0 == "\t" }
                // Unindented lines are yamllint's file headings.
                if body.isEmpty || body.count == line.count { continue }
                let head = body.prefix { $0 != " " }
                guard let colon = head.firstIndex(of: ":") else { continue }
                let row = head[head.startIndex..<colon]
                let column = head[head.index(after: colon)...]
                if isASCIIDigits(row) && isASCIIDigits(column) { count += 1 }
            }
            return count
        }

        /// Python's `str.isdigit()` over the ASCII digits, which is the
        /// only part of it `line:column` can reach.
        static func isASCIIDigits(_ text: Substring) -> Bool {
            !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
        }

        /// Count dangling symlinks among a walked listing.
        public static func brokenLinkCount(
            among entries: [(path: String, isSymlink: Bool, resolves: Bool)]
        ) -> Int {
            entries.count { $0.isSymlink && !$0.resolves }
        }

        /// This audit's report for one package.
        public static func report(
            package: String, yamlIssues issues: Int, brokenLinks links: Int
        ) -> Report {
            Report(
                package: package,
                counters: [yamlIssues: issues, brokenLinks: links])
        }
    }
}
