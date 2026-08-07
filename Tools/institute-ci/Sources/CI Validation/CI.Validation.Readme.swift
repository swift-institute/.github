import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// `[README-*]` — README files conform to the readme skill family
    /// rules.
    ///
    /// The Swift owner of `.github/scripts/validate-readme.py` (Wave 2b
    /// finalization, 2026-05-10). The repository's `readme.family` in
    /// `.github/metadata.yaml` — per Wave 2b Decision 7 — routes it to a
    /// per-family rule subset:
    ///
    /// - **Universal** — `README-017` (exactly one H1, first non-empty
    ///   line), `README-026` (no internal rule-ID citations outside code
    ///   blocks).
    /// - **Family E** (sub-package) — `README-001` (License section),
    ///   `README-008` (Installation with both `.package(` and a
    ///   target-declaration block), `README-013` (Error Handling section
    ///   when the package publicly throws an error type it declares
    ///   itself), `README-016` (no Roadmap/TODO/Changelog).
    ///   `README-003` was removed 2026-07-30, superseded in full by
    ///   swift-institute/.github#126; the rule ID is retired, never
    ///   recycled.
    /// - **Family C** (process) — `README-137` (no Installation, badges,
    ///   or Quick Start), `README-138` (length budget).
    /// - **Family F** (placeholder) — `README-150` (H1 + status
    ///   blockquote only), `README-151` (status value in the canonical
    ///   set). A Family F repository without a README is clean: absence
    ///   *is* the namespace reservation.
    /// - **Family G** (org profile) — `README-116` (no installation
    ///   block). The profile lives at repo-root `profile/README.md` when
    ///   the subject IS the org's `.github` repository, and at
    ///   `.github/profile/README.md` otherwise.
    ///
    /// A repository whose metadata declares `readme.exempt:
    /// vendored-upstream` is skipped and emits nothing — out of scope by
    /// decision, not unclassified by omission. A repository with neither
    /// `family` nor a recognised exemption is `README-family-unset`,
    /// which reads as an oversight rather than a pass.
    ///
    /// ## Correspondence surface
    ///
    /// `exemptions` and `families` mirror the `readme.exempt` and
    /// `readme.family` enums in `metadata-schema.json`. The retired
    /// script's copies (`EXEMPTIONS` / `FAMILIES`) are still the ones the
    /// `[GH-REPO-063]` guard (`validate-schema-workflow-keys.py`) reads
    /// with `ast`, which is why that script is retained after this port —
    /// the guard's re-specification against a Swift consumer follows the
    /// port (swift-institute/.github#404) rather than riding it.
    ///
    /// Message spellings that carry Python `repr` formatting are rendered
    /// through `Retired`, because byte-identity of the sorted TSV against
    /// the retired implementation is the port's one unwaived gate.
    public struct Readme: Validator {
        public let rules: [Rule] = [
            "README-001",
            "README-008",
            "README-013",
            "README-016",
            "README-017",
            "README-026",
            "README-116",
            "README-137",
            "README-138",
            "README-150",
            "README-151",
            "README-family-unset",
            "README-presence",
            "README-read-failed",
        ]
        public let retiredScript: String? = ".github/scripts/validate-readme.py"

        /// Declared exemptions from family routing, per
        /// `metadata-schema.json` `readme.exempt`.
        public static let exemptions: Set<String> = ["vendored-upstream"]

        /// Accepted `readme.family` letters, per `metadata-schema.json`
        /// `readme.family`. B and D are deliberately absent, not retired.
        public static let families: Set<String> = ["A", "C", "E", "F", "G"]

        static let statusValues: Set<String> = [
            "Pre-implementation", "Namespace-reservation", "Unnecessary", "Archived",
        ]

        // The retired patterns, reproduced verbatim; the differential
        // gate is what proves the engines agree. `SkillHygiene.Pattern`
        // is the module's one `finditer`-faithful regex wrapper, reused
        // rather than re-implemented (its own `internalRuleID` covers a
        // different curated segment list, so the pattern itself is not
        // shared).
        typealias Pattern = CI.Validation.SkillHygiene.Pattern

        /// Internal rule-ID citations — `[README-017]`,
        /// `[PLAT-ARCH-008e]` — as the retired `FORBIDDEN_RULE_ID` spelled
        /// them. The curated first segment separates an internal ID from
        /// an external standards citation such as `[RFC-7231]`.
        static let forbiddenRuleID = Pattern(
            #"\[(README|MEM|DOC|API|MOD|PRIM|IMPL|PLAT|ARCH|TEST|SWIFT-TEST|BENCH|INST-TEST|"#
                + #"PATTERN|GH-REPO|SKILL|RES|EXP|BLOG|REFL|AUDIT|CONV|IDX|LEG|NL-WET|RL|"#
                + #"COPY|SEM|API-NAME|API-ERR|API-IMPL|API-LAYER|MEM-COPY|MEM-OWN|MEM-LIFE|"#
                + #"MEM-LINEAR|MEM-REF|MEM-SAFE|MEM-SEND|MEM-UNSAFE|MEM-SPAN|"#
                + #"INFRA|MOD-EXCEPT|CI|README-PROC|SOC|SUPER|HANDOFF|COLLAB|GIT|"#
                + #"FREVIEW|SAVE|DOC-MARKUP|RELEASE|META|REFL-PROC|SKILL-CREATE|"#
                + #"SKILL-LIFE|REFL-PROC)(?:-[A-Z][A-Z0-9]*)*-[0-9]+[a-z]?\]"#)

        static let h1Line = Pattern(#"^#\s+\S"#)
        static let h2Line = Pattern(#"^##\s+\S"#)
        static let fencedBlock = Pattern(#"```.*?```"#, options: [.dotMatchesLineSeparators])
        static let installDependency = Pattern(#"\.package\("#)
        static let installTarget = Pattern(#"\.(?:target|testTarget|executableTarget)\("#)
        static let statusLine = Pattern(#">\s*\*\*Status:\s*([^*]+?)\*\*"#)
        static let errorDeclaration = Pattern(
            #"\b(?:enum|struct|final\s+class|class|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        static let publicThrows = Pattern(#"\bpublic[^\n]*\bthrows\(([^)]+)\)"#)
        static let identifierHead = Pattern(#"^[A-Za-z_][A-Za-z0-9_]*"#)

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            guard let family = Self.family(of: subject) else {
                return [
                    Finding(
                        repository: subject.repository, rule: "README-family-unset",
                        message: ".github/metadata.yaml lacks readme.family field; "
                            + "cannot apply per-family rules")
                ]
            }
            if family == "exempt" {
                // Declared out of scope for routing. Emit nothing — a
                // stated exemption is a clean result, not a suppressed
                // finding.
                return []
            }

            let relative = Self.readmePath(family: family, repository: subject.repository)
            let content: String?
            do {
                content = try subject.text(at: relative)
            } catch {
                // The retired script reported any read failure as a
                // finding, not a crash: the repository routed to a family
                // whose README cannot be read is dirty, not unaskable.
                return [
                    Finding(
                        repository: subject.repository, rule: "README-read-failed",
                        message: "\(subject.path(relative)): could not be read")
                ]
            }
            guard let content else {
                if family == "F" {
                    // Family F can be implicit: no README means namespace
                    // reservation.
                    return []
                }
                return [
                    Finding(
                        repository: subject.repository, rule: "README-presence",
                        message: "family=\(family) but README not found at expected path "
                            + relative)
                ]
            }

            let name = (relative as NSString).lastPathComponent
            var findings = Self.universal(subject.repository, name: name, content: content)
            switch family {
            case "E":
                findings += Self.familyE(subject, name: name, content: content)
            case "C":
                findings += Self.familyC(subject.repository, name: name, content: content)
            case "F":
                findings += Self.familyF(subject.repository, name: name, content: content)
            case "G":
                findings += Self.familyG(subject.repository, name: name, content: content)
            default:
                break  // Family A has no per-family rules in v1.
            }
            return findings
        }
    }
}

extension CI.Validation.Readme {
    /// The family letter, `"exempt"`, or `nil` when unset — the retired
    /// `detect_family`, including its posture that every way of
    /// not-knowing (absent file, unreadable file, unparseable YAML, a
    /// non-mapping where a mapping belongs) is `None`, not an error.
    static func family(of subject: CI.Validation.Subject) -> String? {
        guard let text = try? subject.text(at: ".github/metadata.yaml") else {
            return nil
        }
        guard let document = try? CI.Workflow.YAML.Parser.parse(text),
            let top = document.mapping,
            let readme = top["readme"]?.mapping
        else { return nil }
        if let exempt = readme["exempt"]?.text, exemptions.contains(exempt) {
            return "exempt"
        }
        if let family = readme["family"]?.text, families.contains(family) {
            return family
        }
        return nil
    }

    /// Where the family's README lives, relative to the subject root.
    ///
    /// Family G org profiles live in the org's special `.github` repo at
    /// `profile/README.md`. When the repository under validation IS that
    /// `.github` repo, the profile is at repo-root `profile/README.md` —
    /// not a nested `.github/profile/README.md`, which is the
    /// org-relative view and wrong inside the repo itself.
    static func readmePath(family: String, repository: String) -> String {
        guard family == "G" else { return "README.md" }
        let lastComponent = repository.split(separator: "/").last.map(String.init) ?? repository
        return lastComponent == ".github"
            ? "profile/README.md"
            : ".github/profile/README.md"
    }

    /// Fenced ``` … ``` code blocks removed, for the rule-citation and
    /// H1 scans.
    static func strippingCodeBlocks(_ text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        for match in fencedBlock.matches(in: text) {
            result += text[cursor..<match.range.lowerBound]
            cursor = match.range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// `str.splitlines()` — no trailing empty line for a trailing
    /// newline, and `\r`, `\n`, `\r\n` each terminate a line. The
    /// distinction is load-bearing for `README-138`'s line count.
    static func splitLines(_ text: String) -> [Substring] {
        var lines: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\n" || character == "\r" || character == "\r\n" {
                lines.append(text[start..<index])
                index = text.index(after: index)
                start = index
            } else {
                index = text.index(after: index)
            }
        }
        if start < text.endIndex { lines.append(text[start...]) }
        return lines
    }

    /// The first `limit` code points, as Python's `[:n]` slices.
    static func prefix(_ text: some StringProtocol, _ limit: Int) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit)))
    }

    static func universal(
        _ repository: String, name: String, content: String
    ) -> [CI.Validation.Finding] {
        typealias Finding = CI.Validation.Finding
        var findings: [Finding] = []
        let lines = splitLines(content)
        let nonblank = lines.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // [README-017] H1 present and exactly one. Counted over
        // fence-stripped content (mirroring the [README-026] scan) so a
        // shell comment inside a ```bash fence is not miscounted as an H1.
        let stripped = strippingCodeBlocks(content)
        let h1Count = splitLines(stripped)
            .count { h1Line.firstMatch(in: String($0)) != nil }
        if h1Count == 0 {
            findings.append(
                Finding(
                    repository: repository, rule: "README-017",
                    message: "\(name): missing H1 title (first heading must be `# `)"))
        } else if h1Count > 1 {
            findings.append(
                Finding(
                    repository: repository, rule: "README-017",
                    message: "\(name): \(h1Count) H1 headings found; exactly one required"))
        }
        if let first = nonblank.first, h1Line.firstMatch(in: String(first)) == nil {
            findings.append(
                Finding(
                    repository: repository, rule: "README-017",
                    message: "\(name): first non-empty line is not H1 "
                        + "(got \(CI.Validation.Retired.quoted(prefix(first, 80))))"))
        }
        // [README-026] no internal rule-ID citations outside code blocks.
        // One finding suffices.
        if let match = forbiddenRuleID.firstMatch(in: stripped) {
            findings.append(
                Finding(
                    repository: repository, rule: "README-026",
                    message: "\(name): contains internal rule-ID citation \(match.whole) "
                        + "(forbidden in published READMEs)"))
        }
        return findings
    }

    static func familyE(
        _ subject: CI.Validation.Subject, name: String, content: String
    ) -> [CI.Validation.Finding] {
        typealias Finding = CI.Validation.Finding
        var findings: [Finding] = []
        // [README-003] removed 2026-07-30: superseded in full by
        // swift-institute/.github#126.
        // [README-001] License section present.
        if !content.contains("## License") {
            findings.append(
                Finding(
                    repository: subject.repository, rule: "README-001",
                    message: "\(name): missing `## License` section"))
        }
        // [README-008] Installation section presence, then both the
        // `.package(` and target-declaration blocks within it.
        if let heading = content.range(of: "## Installation") {
            let searchStart = content.index(after: heading.lowerBound)
            let nextSection = content.range(
                of: "\n## ", range: searchStart..<content.endIndex)
            let section = String(
                content[heading.lowerBound..<(nextSection?.lowerBound ?? content.endIndex)])
            if installDependency.firstMatch(in: section) == nil {
                findings.append(
                    Finding(
                        repository: subject.repository, rule: "README-008",
                        message: "\(name): Installation section missing `.package(...)` "
                            + "dependency block"))
            }
            if installTarget.firstMatch(in: section) == nil {
                findings.append(
                    Finding(
                        repository: subject.repository, rule: "README-008",
                        message: "\(name): Installation section missing "
                            + "`.target(dependencies: ...)` block"))
            }
        } else {
            findings.append(
                Finding(
                    repository: subject.repository, rule: "README-008",
                    message: "\(name): missing `## Installation` section"))
        }
        // [README-013] Error Handling threshold (Wave 2b Decision 5).
        if declaresThrownError(subject), !content.contains("## Error Handling") {
            findings.append(
                Finding(
                    repository: subject.repository, rule: "README-013",
                    message: "\(name): package has public throws(NonNever) signatures but "
                        + "README lacks `## Error Handling` section (Wave 2b finalization "
                        + "Decision 5 threshold)"))
        }
        // [README-016] forbidden sections.
        for forbidden in ["## Roadmap", "## TODO", "## Changelog"]
        where content.contains(forbidden) {
            findings.append(
                Finding(
                    repository: subject.repository, rule: "README-016",
                    message: "\(name): contains forbidden section "
                        + CI.Validation.Retired.quoted(forbidden)))
        }
        return findings
    }

    /// `[README-013]`'s threshold: the package publicly throws an error
    /// type it DECLARES in its own `Sources`.
    ///
    /// A facade / re-export package throws a *dependency-owned* error
    /// type and declares no error type of its own. The README-013 remedy
    /// — documenting the package's OWN error tree — is impossible for
    /// such a package, so it must not fire. The finding keys on
    /// ownership: a public `throws(T)` whose `T` resolves to a simple
    /// name the package itself declares. Type aliases are excluded on
    /// purpose: `typealias Error = Dep.Error` re-exports a dependency's
    /// error and is not ownership.
    static func declaresThrownError(_ subject: CI.Validation.Subject) -> Bool {
        let sources = subject.path("Sources")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sources, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return false }
        var declared: Set<String> = []
        var thrown: Set<String> = []
        let enumerator = FileManager.default.enumerator(atPath: sources)
        while let element = enumerator?.nextObject() as? String {
            guard element.hasSuffix(".swift"),
                let data = FileManager.default.contents(atPath: "\(sources)/\(element)")
            else { continue }
            let content = String(decoding: data, as: UTF8.self)
            for match in errorDeclaration.matches(in: content) {
                guard let name = match.groups[1], name.contains("Error") else { continue }
                declared.insert(name)
            }
            for match in publicThrows.matches(in: content) {
                let raw = (match.groups[1] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, raw != "Never" else { continue }
                let name = thrownTypeName(raw)
                if !name.isEmpty { thrown.insert(name) }
            }
        }
        return !declared.isDisjoint(with: thrown)
    }

    /// A typed-throws payload reduced to the error type's own simple
    /// name: `Self.Error` → `Error`, `MyError<Token>` → `MyError`.
    static func thrownTypeName(_ thrown: String) -> String {
        var base = thrown
        if let angle = base.range(of: "<") { base = String(base[..<angle.lowerBound]) }
        if let bracket = base.range(of: "[") { base = String(base[..<bracket.lowerBound]) }
        let tail = (base.split(separator: ".").last.map(String.init) ?? base)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return identifierHead.firstMatch(in: tail)?.whole ?? ""
    }

    static func familyC(
        _ repository: String, name: String, content: String
    ) -> [CI.Validation.Finding] {
        typealias Finding = CI.Validation.Finding
        var findings: [Finding] = []
        // [README-137] no Installation / badges / Quick Start. The badge
        // probe is anchored at the start of the document — the retired
        // `BADGE_LINE` was compiled without MULTILINE, and its reach is
        // part of the published rule.
        if content.contains("## Installation") {
            findings.append(
                Finding(
                    repository: repository, rule: "README-137",
                    message: "\(name): process README has `## Installation` section (forbidden)"))
        }
        if content.hasPrefix("![") {
            findings.append(
                Finding(
                    repository: repository, rule: "README-137",
                    message: "\(name): process README has badges (forbidden)"))
        }
        if content.contains("## Quick Start") {
            findings.append(
                Finding(
                    repository: repository, rule: "README-137",
                    message: "\(name): process README has `## Quick Start` (forbidden)"))
        }
        // [README-138] length budget.
        let lineCount = splitLines(content).count
        if lineCount > 80 {
            findings.append(
                Finding(
                    repository: repository, rule: "README-138",
                    message: "\(name): process README is \(lineCount) lines (>80 suggests "
                        + "content should relocate per [README-138])"))
        }
        return findings
    }

    static func familyF(
        _ repository: String, name: String, content: String
    ) -> [CI.Validation.Finding] {
        typealias Finding = CI.Validation.Finding
        var findings: [Finding] = []
        // [README-150] H1 + status blockquote only — no other ##
        // sections. License is universal; allowed as the one exception.
        let extraH2 = splitLines(content).filter {
            h2Line.firstMatch(in: String($0)) != nil && !$0.contains("## License")
        }
        if let first = extraH2.first {
            findings.append(
                Finding(
                    repository: repository, rule: "README-150",
                    message: "\(name): Family F README has extra ## sections "
                        + "(first: \(CI.Validation.Retired.quoted(prefix(first, 60)))); "
                        + "should be H1 + status blockquote only"))
        }
        // [README-151] status value enumerated.
        if let match = statusLine.firstMatch(in: content),
            let status = match.groups[1]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !statusValues.contains(status)
        {
            findings.append(
                Finding(
                    repository: repository, rule: "README-151",
                    message: "\(name): Family F status \(CI.Validation.Retired.quoted(status)) "
                        + "not in canonical set \(CI.Validation.Retired.list(statusValues.sorted()))"))
        }
        return findings
    }

    static func familyG(
        _ repository: String, name: String, content: String
    ) -> [CI.Validation.Finding] {
        guard content.contains("## Installation") else { return [] }
        // [README-116] org profile MUST NOT include installation block.
        return [
            CI.Validation.Finding(
                repository: repository, rule: "README-116",
                message: "\(name): org-profile README has `## Installation` section (forbidden)")
        ]
    }
}
