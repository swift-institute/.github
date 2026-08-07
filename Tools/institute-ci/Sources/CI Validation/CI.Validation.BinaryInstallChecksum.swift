import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// `[CI-082]` — a curl-fetched binary must be verified with
    /// `sha256sum -c` before it is installed, and the verification must
    /// fail closed.
    ///
    /// Four failure modes, each its own finding so a step with more than
    /// one is reported more than once:
    ///
    /// - **A** `curl … | bash` / `| sh` — no verification is possible by
    ///   construction. Fires regardless of install indicators.
    /// - **B** a curl fetch plus an install indicator in the same `run:`
    ///   block, with no `sha256sum -c` in that block.
    /// - **C** `sha256sum … || true` — the swallowed exit code nullifies
    ///   the gate.
    /// - **D** `sha256sum … 2>/dev/null` — the FAIL message goes to
    ///   stderr, so suppressing stderr disables the gate's diagnostic
    ///   surface.
    ///
    /// **The run block is the unit**, not the file: a checksum verified
    /// in a *different* step does not gate this one, because each `run:`
    /// is a separate shell and nothing carries between them but the
    /// filesystem.
    ///
    /// `apt-get install` does not fire — apt verifies signatures through
    /// its keyring. A curl-fetched apt *keyring* does fire: the keyring
    /// is the trust root for every package installed after it.
    ///
    /// Detection is over the shell text, with no shell parser. That is a
    /// deliberate ceiling: the rule asks whether the conventional
    /// verification shape is present, and a validator that tried to
    /// evaluate the script would answer a question the rule does not ask.
    public struct BinaryInstallChecksum: Validator {
        public static let rule: Rule = "CI-082"

        public let rules: [Rule] = [Self.rule]
        public let retiredScript: String? = ".github/scripts/validate-binary-install-checksum.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let (documents, refusals) = try subject.workflows(citing: Self.rule)
            var findings = refusals
            for document in documents {
                for job in document.jobs {
                    for step in Self.steps(of: job) {
                        guard let script = step.run, !script.allSatisfy(\.isWhitespace) else {
                            continue
                        }
                        findings += Self.findings(
                            in: script,
                            repository: subject.repository,
                            workflow: document.name,
                            job: job.name,
                            step: step.label
                        )
                    }
                }
            }
            return findings
        }

        // MARK: - Steps

        /// One step, with the label a finding cites it by.
        struct Step {
            let run: String?
            /// The step's `name:`, or `#<index>` when it has none — and
            /// the index counts **every** entry of `steps:`, including
            /// malformed ones, so the number a reader counts down the
            /// file is the number they are given.
            let label: String
        }

        static func steps(of job: CI.Workflow.Job) -> [Step] {
            guard let entries = job.body["steps"]?.sequence else { return [] }
            return entries.enumerated().compactMap { index, node in
                guard let step = node.mapping else { return nil }
                let name = step["name"]?.text
                return Step(
                    run: step["run"]?.text,
                    label: name.map { $0.isEmpty ? "#\(index)" : $0 } ?? "#\(index)"
                )
            }
        }

        // MARK: - The four failure modes

        static func findings(
            in script: String,
            repository: String,
            workflow: String,
            job: String,
            step: String
        ) -> [Finding] {
            var findings: [Finding] = []
            func report(_ message: String) {
                findings.append(Finding(repository: repository, rule: Self.rule, message: message))
            }
            let cited = "\(workflow): job \(Self.quoted(job)) step \(Self.quoted(step))"

            if Self.pipesCurlIntoShell(script) {
                report(
                    "\(cited) pipes curl output directly into a shell (`curl ... | bash` or "
                        + "`curl ... | sh`) — per [CI-082] this is forbidden because no checksum "
                        + "verification is possible by construction. Fetch to a file, "
                        + "`sha256sum -c` against a pinned digest, then exec."
                )
            }
            if Self.swallowsExitCode(script) {
                report(
                    "\(cited) has `sha256sum ... || true` — per [CI-082] the verification step "
                        + "MUST fail-closed. The `|| true` swallow nullifies the gate; remove it "
                        + "so a digest mismatch fails the job."
                )
            }
            if Self.swallowsDiagnostics(script) {
                report(
                    "\(cited) has `sha256sum ... 2>/dev/null` — per [CI-082] the FAIL message "
                        + "MUST be visible. Suppressing stderr disables the gate's diagnostic "
                        + "surface."
                )
            }
            if Self.fetchesWithCurl(script), Self.installsBinary(script),
                !Self.verifiesChecksum(script)
            {
                report(
                    "\(cited) fetches an artifact via curl AND installs it (mv to bin path, "
                        + "chmod +x, tar/unzip, apt keyring) WITHOUT `sha256sum -c` verification "
                        + "in the same run-block — per [CI-082] every curl-fetched binary install "
                        + "MUST verify the artifact against a pinned SHA-256 before installation. "
                        + "Reference shape: see the lychee install in [CI-082] body."
                )
            }
            return findings
        }

        /// A `curl` invocation carrying one of the fetch-to-file flag
        /// spellings. Real installs converge on `-fsSL`; the spelled-out
        /// forms are recognised too, so an equivalent invocation does not
        /// silently under-fire.
        static func fetchesWithCurl(_ script: String) -> Bool {
            Self.scan(script) { line, index in
                guard Self.word(line, at: index, is: "curl") else { return false }
                let rest = line[index...]
                return Self.contains(rest, wordSuffixed: "-fsSL")
                    || Self.contains(rest, wordSuffixed: "-sSL")
                    || Self.contains(rest, wordSuffixed: "-Lf")
                    || Self.contains(rest, wordSuffixed: "-fL")
                    || Self.containsSpelledOutFetchFlags(rest)
            }
        }

        /// `--fail --silent --location`, or `--silent --location`.
        static func containsSpelledOutFetchFlags(_ text: Substring) -> Bool {
            Self.contains(text, whitespaceSeparated: ["--fail", "--silent", "--location"])
                || Self.contains(text, whitespaceSeparated: ["--silent", "--location"])
        }

        /// `curl … | bash` or `curl … | sh`, within one line and with no
        /// second pipe between them.
        static func pipesCurlIntoShell(_ script: String) -> Bool {
            Self.scan(script) { line, index in
                guard Self.word(line, at: index, is: "curl") else { return false }
                var rest = line[index...].dropFirst("curl".count)
                guard let pipe = rest.firstIndex(of: "|") else { return false }
                rest = rest[rest.index(after: pipe)...]
                guard !rest.contains("|") else { return false }
                for shell in ["bash", "sh"] {
                    var cursor = rest.startIndex
                    while cursor < rest.endIndex {
                        if Self.word(rest, at: cursor, is: shell) {
                            let after = rest.index(cursor, offsetBy: shell.count)
                            if after == rest.endIndex { return true }
                            let character = rest[after]
                            if character.isWhitespace || character == "\\" || character == ";" {
                                return true
                            }
                        }
                        cursor = rest.index(after: cursor)
                    }
                }
                return false
            }
        }

        /// The presence of any binary-install indicator in the block —
        /// what distinguishes an install path from a data or config
        /// fetch.
        static func installsBinary(_ script: String) -> Bool {
            Self.scan(script) { line, index in
                if Self.word(line, at: index, is: "unzip") { return true }
                if Self.word(line, at: index, is: "gunzip") { return true }
                let rest = line[index...]
                if Self.word(line, at: index, is: "mv") { return Self.namesBinaryDirectory(rest) }
                if Self.word(line, at: index, is: "chmod") {
                    return Self.contains(rest, wordSuffixed: "+x")
                }
                if Self.word(line, at: index, is: "tar") { return Self.extractsArchive(rest) }
                if Self.word(line, at: index, is: "install") { return Self.installsWithMode(rest) }
                if Self.word(line, at: index, is: "tee") {
                    return rest.contains("/etc/apt/keyrings/")
                }
                if Self.word(line, at: index, is: "xz") {
                    return Self.contains(rest.dropFirst("xz".count), leadingSpaceThen: "-d")
                }
                return false
            }
        }

        /// A destination on the executable path. `/bin/` counts only when
        /// it is the whole segment — `/sbin/` and `/usr/sbin/` are not
        /// this indicator.
        static func namesBinaryDirectory(_ text: Substring) -> Bool {
            if text.contains("/usr/local/bin/") || text.contains("/usr/bin/") { return true }
            var cursor = text.startIndex
            while cursor < text.endIndex {
                if text[cursor...].hasPrefix("/bin/") {
                    if cursor == text.startIndex { return true }
                    if !Self.isWordCharacter(text[text.index(before: cursor)]) { return true }
                }
                cursor = text.index(after: cursor)
            }
            return false
        }

        /// `tar -x…`, or a `tar x…` form carrying one of the classic
        /// mode letters.
        static func extractsArchive(_ text: Substring) -> Bool {
            if text.contains("-x") { return true }
            guard let x = text.firstIndex(of: "x") else { return false }
            let rest = text[text.index(after: x)...]
            var cursor = rest.startIndex
            while cursor < rest.endIndex {
                if Self.isWordBoundary(rest, at: cursor) {
                    var end = cursor
                    while end < rest.endIndex, "Jcjzv".contains(rest[end]) {
                        end = rest.index(after: end)
                    }
                    if end > cursor,
                        end == rest.endIndex || !Self.isWordCharacter(rest[end])
                    {
                        return true
                    }
                }
                cursor = rest.index(after: cursor)
            }
            return false
        }

        /// `install -m<mode>` — the Unix install command with an explicit
        /// mode, as an install path uses.
        static func installsWithMode(_ text: Substring) -> Bool {
            var rest = text.dropFirst("install".count)
            guard let first = rest.first, first.isWhitespace else { return false }
            rest = rest.drop(while: \.isWhitespace)
            guard rest.first == "-" else { return false }
            rest = rest.dropFirst()
            let flags = rest.prefix(while: Self.isWordCharacter)
            guard let m = flags.lastIndex(of: "m") else { return false }
            let after = flags.index(after: m)
            return after < flags.endIndex && ("0"..."9").contains(flags[after])
        }

        /// `sha256sum … -c` / `--check` within one line, before any pipe.
        static func verifiesChecksum(_ script: String) -> Bool {
            Self.scan(script) { line, index in
                guard Self.word(line, at: index, is: "sha256sum") else { return false }
                let rest = line[index...].prefix { $0 != "|" }
                return Self.contains(rest, wordSuffixed: "-c")
                    || Self.contains(rest, wordSuffixed: "--check")
            }
        }

        /// `sha256sum … || true` (or `|| :`) within one line.
        static func swallowsExitCode(_ script: String) -> Bool {
            Self.scan(script) { line, index in
                guard Self.word(line, at: index, is: "sha256sum") else { return false }
                var rest = line[index...]
                guard let or = rest.range(of: "||") else { return false }
                rest = rest[or.upperBound...].drop(while: \.isWhitespace)
                // `true\b` and `:\b` — the second requires a word
                // character after the colon, which is the retired
                // pattern's own quirk and is kept rather than quietly
                // widened.
                if rest.hasPrefix("true") {
                    let after = rest.dropFirst(4)
                    return after.isEmpty || !Self.isWordCharacter(after.first!)
                }
                if rest.hasPrefix(":") {
                    let after = rest.dropFirst()
                    return !after.isEmpty && Self.isWordCharacter(after.first!)
                }
                return false
            }
        }

        /// `sha256sum … 2>/dev/null` within one line.
        static func swallowsDiagnostics(_ script: String) -> Bool {
            Self.scan(script) { line, index in
                guard Self.word(line, at: index, is: "sha256sum") else { return false }
                let rest = line[index...]
                guard let found = rest.range(of: "2>/dev/null") else { return false }
                return found.upperBound == rest.endIndex
                    || !Self.isWordCharacter(rest[found.upperBound])
            }
        }

        // MARK: - Shell-text scanning

        /// Run `predicate` at every position of every line, stopping at
        /// the first true. Every pattern here is line-scoped: a `run:`
        /// block is many commands, and a `curl` on one line has nothing
        /// to do with a flag on another.
        static func scan(
            _ script: String,
            _ predicate: (Substring, Substring.Index) -> Bool
        ) -> Bool {
            for line in script.split(separator: "\n", omittingEmptySubsequences: false) {
                var cursor = line.startIndex
                while cursor < line.endIndex {
                    if predicate(line, cursor) { return true }
                    cursor = line.index(after: cursor)
                }
            }
            return false
        }

        static func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        /// Whether a word boundary sits immediately before `index`.
        static func isWordBoundary(_ text: Substring, at index: Substring.Index) -> Bool {
            guard index < text.endIndex else { return false }
            let inside = Self.isWordCharacter(text[index])
            guard index > text.startIndex else { return inside }
            return inside != Self.isWordCharacter(text[text.index(before: index)])
        }

        /// `\bword\b` anchored at `index`.
        static func word(_ text: Substring, at index: Substring.Index, is word: String) -> Bool {
            guard text[index...].hasPrefix(word) else { return false }
            if index > text.startIndex, Self.isWordCharacter(text[text.index(before: index)]) {
                return false
            }
            let after = text.index(index, offsetBy: word.count)
            return after == text.endIndex || !Self.isWordCharacter(text[after])
        }

        /// `token` anywhere in `text`, followed by a word boundary.
        static func contains(_ text: Substring, wordSuffixed token: String) -> Bool {
            var cursor = text.startIndex
            while cursor < text.endIndex {
                if text[cursor...].hasPrefix(token) {
                    let after = text.index(cursor, offsetBy: token.count)
                    if after == text.endIndex || !Self.isWordCharacter(text[after]) { return true }
                }
                cursor = text.index(after: cursor)
            }
            return false
        }

        /// Whitespace then `token`, followed by a word boundary — the
        /// `xz -d` shape.
        static func contains(_ text: Substring, leadingSpaceThen token: String) -> Bool {
            guard let first = text.first, first.isWhitespace else { return false }
            let rest = text.drop(while: \.isWhitespace)
            guard rest.hasPrefix(token) else { return false }
            let after = rest.dropFirst(token.count)
            return after.isEmpty || !Self.isWordCharacter(after.first!)
        }

        /// The tokens in order, each pair separated by at least one run
        /// of whitespace, with a word boundary after the last.
        static func contains(_ text: Substring, whitespaceSeparated tokens: [String]) -> Bool {
            var rest = text
            for (offset, token) in tokens.enumerated() {
                guard let found = rest.range(of: token) else { return false }
                rest = rest[found.upperBound...]
                let isLast = offset == tokens.count - 1
                if isLast {
                    return rest.isEmpty || !Self.isWordCharacter(rest.first!)
                }
                guard let first = rest.first, first.isWhitespace else { return false }
                rest = rest.drop(while: \.isWhitespace)
            }
            return false
        }

        /// Python's `repr` of a string, which the retired messages
        /// interpolated with `!r`. Preserved because the finding text is
        /// the differential gate's comparand.
        static func quoted(_ value: String) -> String {
            if value.contains("'") && !value.contains("\"") { return "\"\(value)\"" }
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            return "'\(escaped)'"
        }
    }
}
