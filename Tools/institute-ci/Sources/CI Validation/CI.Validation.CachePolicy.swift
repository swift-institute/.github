import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-040]` no `.build/` cache, and `[CI-042]` no `restore-keys`.
    ///
    /// Two rules, one walk, because both are questions about the same
    /// point in the document — an `actions/cache` step's `with:` block —
    /// and a single step can violate both.
    ///
    /// `[CI-040]` is carve-out free. The L1-embedded-job exemption that
    /// stood until 2026-07-31 is retired (swift-institute/.github#161):
    /// the `embedded` job in swift-primitives/.github was restoring ~84MB
    /// of `.build` and reporting "Build complete!" with zero `Compiling`
    /// lines, so the leg's green attested a cache restore rather than a
    /// compile. An exact key does not save it — the key hashed only the
    /// manifests, so it encoded neither the toolchain nor branch-pinned
    /// dependency contents. Under gitignored `Package.resolved` plus
    /// branch pins, no key can prove a `.build` represents the resolved
    /// graph.
    ///
    /// `[CI-042]` is carve-out free for the same reason one layer up: a
    /// prefix fallback serves *some* earlier cache, and which one is not
    /// a property the workflow states. Tool-binary caches are permitted
    /// by `[CI-044]` and are outside `[CI-040]`'s scope — their `path:`
    /// does not name `.build` — but they are inside `[CI-042]`'s.
    public struct CachePolicy: Validator {
        public let rules: [Rule] = ["CI-040", "CI-042"]
        public let retiredScript: String? = ".github/scripts/validate-cache-policy.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            // Parse refusals cite CI-040, the primary of the pair, as the
            // retired validator did. A document that will not parse does
            // not violate one of the two rather than the other, but the
            // TSV's rule column needs a value.
            let (documents, refusals) = try subject.workflows(citing: rules[0])
            var findings = refusals
            for document in documents {
                for job in document.jobs {
                    for step in job.steps where Self.invokesCache(step) {
                        guard let with = step["with"]?.mapping else { continue }
                        findings += Self.findings(
                            in: with, repository: subject.repository,
                            document: document.name, job: job.name)
                    }
                }
            }
            return findings
        }

        /// Whether the step invokes `actions/cache`, at any version.
        static func invokesCache(_ step: CI.Workflow.YAML.Mapping) -> Bool {
            (step["uses"]?.pythonString ?? "").hasPrefix("actions/cache")
        }

        /// The violations one cache step's `with:` block carries. A step
        /// can carry both.
        static func findings(
            in with: CI.Workflow.YAML.Mapping, repository: String, document: String, job: String
        ) -> [Finding] {
            var findings: [Finding] = []
            if let path = with["path"]?.text, Self.namesBuildDirectory(path) {
                findings.append(
                    Finding(
                        repository: repository, rule: "CI-040",
                        message: Self.buildCacheMessage(
                            document: document, job: job,
                            path: CI.Workflow.YAML.Node.repr(path))))
            }
            if let keys = with["restore-keys"] {
                let preview = Self.preview(of: keys.pythonString)
                findings.append(
                    Finding(
                        repository: repository, rule: "CI-042",
                        message: Self.restoreKeysMessage(
                            document: document, job: job,
                            preview: CI.Workflow.YAML.Node.repr(preview))))
            }
            return findings
        }

        /// The `restore-keys` value as the finding quotes it: newlines
        /// flattened, ends stripped, truncated.
        ///
        /// Truncation counts **code points**, as Python's slice does, not
        /// grapheme clusters — the two differ on any composed character
        /// sitting at the boundary, and a finding that disagrees with its
        /// retired counterpart by one scalar is still a disagreement.
        static func preview(of keys: String) -> String {
            let whitespace: Set<Character> = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}"]
            var flattened = Substring(keys.map { $0 == "\n" ? " " : $0 })
            while let first = flattened.first, whitespace.contains(first) {
                flattened = flattened.dropFirst()
            }
            while let last = flattened.last, whitespace.contains(last) {
                flattened = flattened.dropLast()
            }
            return String(String.UnicodeScalarView(flattened.unicodeScalars.prefix(80)))
        }

        /// Whether any line of the cache path names `.build` as a whole
        /// path component.
        ///
        /// Component-wise, not substring: `mybuild` and `.build-extra`
        /// are different directories and the corpus asserts both. Lines
        /// are examined independently because a `path:` block scalar
        /// carries several.
        static func namesBuildDirectory(_ path: String) -> Bool {
            path.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
                var remainder = Substring(line)
                while let range = remainder.range(of: ".build") {
                    let precedes =
                        range.lowerBound == remainder.startIndex
                        || remainder[remainder.index(before: range.lowerBound)] == "/"
                    let follows =
                        range.upperBound == remainder.endIndex
                        || remainder[range.upperBound] == "/"
                    if precedes && follows { return true }
                    remainder = remainder[range.lowerBound...].dropFirst()
                }
                return false
            }
        }

        static func buildCacheMessage(document: String, job: String, path: String) -> String {
            """
            \(document): job \(CI.Workflow.YAML.Node.repr(job)) caches `.build/` via \
            `actions/cache` per [CI-040] — the no-`.build/`-cache rule is \
            permanent AND carve-out-free under the gitignored-Package.resolved \
            + branch-pinned-deps constraint set. No key, however exact, can \
            prove a restored `.build` matches the resolved graph or the running \
            toolchain; a hit turns the job's green into evidence of a restore \
            rather than a compile (swift-institute/.github#161). path=\(path)
            """
        }

        static func restoreKeysMessage(document: String, job: String, preview: String) -> String {
            """
            \(document): job \(CI.Workflow.YAML.Node.repr(job)) cache step uses \
            `restore-keys:` per [CI-042] — partial-prefix fallback silently \
            serves stale state. Cache hits MUST be exact-match-only (remove \
            `restore-keys:`). restore-keys preview: \(preview)
            """
        }
    }
}
