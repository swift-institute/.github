import Foundation

extension Rulebook {
    /// The canon guard: four checks over a markdown corpus, against a
    /// prune-only baseline.
    ///
    /// It exists because the 2026-07-05 corpus review measured the split
    /// directly — the guarded layer (Swift source, which swift-linter
    /// reads) was healthy, and the unguarded layer (the prose stating the
    /// rules) held eight fatal cross-rule contradictions and about thirty
    /// dangling references. Every one of them was in a file no gate read.
    ///
    /// Report-only by default; `--enforce` is the wired mode, and
    /// `sync-skills.sh` aborts a sync on any non-baselined finding. That
    /// wiring flip required an explicit principal yes, which was given on
    /// 2026-07-06 — the constraint is satisfied, not pending.
    public struct Audit: Sendable {
        public let corpus: Corpus
        public let baseline: Baseline
        public let allowlist: Allowlist
        /// The root the artifact check resolves relative paths against.
        public let developerRoot: String

        public init(
            corpus: Corpus, baseline: Baseline, allowlist: Allowlist, developerRoot: String
        ) {
            self.corpus = corpus
            self.baseline = baseline
            self.allowlist = allowlist
            self.developerRoot = developerRoot
        }

        /// Run the named checks. `nil` runs all four.
        public func run(_ checks: [Check]? = nil) -> Report {
            let active = checks ?? Check.allCases
            let definitions = Self.definitions(in: corpus)
            var results: [Check: [Finding]] = [:]
            for check in active {
                results[check] =
                    switch check {
                    case .citations: citations(against: definitions)
                    case .duplicates: duplicates(in: definitions)
                    case .artifacts: artifacts()
                    case .hubIndex: hubIndex()
                    }
            }
            return Report(
                results: results, documentCount: corpus.documents.count,
                definedCount: definitions.count, baseline: baseline)
        }
    }
}

// MARK: - The definition census

extension Rulebook.Audit {
    /// Every identifier the corpus defines, and where.
    public static func definitions(in corpus: Rulebook.Corpus) -> [Rulebook.Identifier: [Rulebook.Definition]]
    {
        var definitions: [Rulebook.Identifier: [Rulebook.Definition]] = [:]
        for document in corpus.documents {
            for line in document.prose {
                guard let identifier = Rulebook.Document.headingDefinition(on: line.text) else {
                    continue
                }
                definitions[identifier, default: []]
                    .append(.init(alias: document.alias, line: line.number, form: .heading))
            }
            for identifier in registered(in: document).sorted() {
                definitions[identifier, default: []]
                    .append(.init(alias: document.alias, line: 0, form: .registry))
            }
        }
        return definitions
    }

    /// The identifiers a file's **Rules in this file** header enumerates.
    ///
    /// Ranges expand **fully** here, unlike in a citation: the header is
    /// an explicit claim of each member, so `[X-010]–[X-012]` in a
    /// registry claims three rules and the hub check will ask the file to
    /// carry all three.
    public static func registered(in document: Rulebook.Document) -> Set<Rulebook.Identifier> {
        var identifiers: Set<Rulebook.Identifier> = []
        for line in document.prose where Rulebook.Document.isRegistryHeader(line.text) {
            for citation in Rulebook.Citation.scan(line.text) {
                switch citation.form {
                case .crossRange(let start, let end), .inBracketRange(let start, let end):
                    identifiers.formUnion(Rulebook.Identifier.range(from: start, to: end))
                case .single(let identifier):
                    identifiers.insert(identifier)
                case .wildcard:
                    continue
                }
            }
        }
        return identifiers
    }
}

// MARK: - Check 1: citations resolve

extension Rulebook.Audit {
    /// A citation of a **retired** identifier is deliberate when the line
    /// says so. Supersession idioms — a redirect notice, a burned slot,
    /// an absorption note — mean the author knows the identifier is gone
    /// and is saying so on purpose. A dangling cite without one is the
    /// rot this check exists to catch.
    static let historicalMarkers = [
        "subsume", "demoted", "burned", "absorbed", "superseded", "supersedes",
        "formerly", "renumbered", "retired", "the former", "ghost", "deleted",
        "no rule body", "slot stays", "never defined", "redirect",
    ]

    /// Template and example prefixes that never name a real rule.
    /// `CLAIM` and `ASSUMP` are research-document registry families, not
    /// rulebook identifiers.
    static let placeholderPrefixes: Set<String> = [
        "PREFIX", "X", "ID", "ID-PREFIX", "FOO", "OTHER", "OTHER-ID", "CLAIM", "ASSUMP",
    ]

    func citations(against definitions: [Rulebook.Identifier: [Rulebook.Definition]]) -> [Rulebook.Finding] {
        let defined = Set(definitions.keys)
        func isFamily(_ prefix: String) -> Bool {
            defined.contains { $0.rawValue.hasPrefix("\(prefix)-") }
        }

        var findings: [Rulebook.Finding] = []
        for document in corpus.documents {
            for line in document.prose {
                let lowered = line.text.lowercased()
                guard !Self.historicalMarkers.contains(where: lowered.contains) else { continue }
                func report(_ token: String, _ message: String) {
                    findings.append(
                        .init(
                            check: .citations, key: "\(document.alias) [\(token)]",
                            message: "\(document.alias):\(line.number) \(message)"))
                }
                for citation in Rulebook.Citation.scan(line.text) {
                    switch citation.form {
                    case .crossRange(let start, let end):
                        for endpoint in [start, end] where !defined.contains(endpoint) {
                            report(
                                endpoint.rawValue,
                                "range endpoint [\(endpoint)] unresolved")
                        }
                    case .inBracketRange(let start, let end):
                        for endpoint in [start, end] where !defined.contains(endpoint) {
                            report(
                                endpoint.rawValue,
                                "in-bracket range endpoint [\(endpoint)] unresolved")
                        }
                    case .wildcard(let family):
                        guard !Self.placeholderPrefixes.contains(family) else { continue }
                        guard !isFamily(family) else { continue }
                        report("\(family)-*", "wildcard [\(family)-*] matches no defined id")
                    case .single(let identifier):
                        guard !Self.isPlaceholder(identifier.rawValue) else { continue }
                        guard !defined.contains(identifier) else { continue }
                        // A word-form token naming a defined family is a
                        // prefix reference — "the [MEM-*] family" written
                        // without the star — not a dangle.
                        guard
                            !(Rulebook.Identifier.isWord(identifier.rawValue)
                                && isFamily(identifier.rawValue))
                        else { continue }
                        report(identifier.rawValue, "citation [\(identifier)] unresolved")
                    }
                }
            }
        }
        return Self.deduplicated(findings)
    }

    /// Whether a bracketed token is template grammar rather than a
    /// citation.
    static func isPlaceholder(_ token: String) -> Bool {
        let family = token.components(separatedBy: "-").first ?? token
        if placeholderPrefixes.contains(family) { return true }
        if token.hasPrefix("{") || token.hasPrefix("<") { return true }
        return matchesPlaceholderGrammar(token)
    }

    /// The numeric-part placeholder grammar: a token whose numeric slot
    /// is written as `NNN`, a bare `N`, `NUMBER`, `WORD`, `SECTION`, or
    /// `XXX`.
    static func matchesPlaceholderGrammar(_ token: String) -> Bool {
        if token.hasPrefix("{") && token.hasSuffix("}") { return true }
        if token.hasPrefix("<") && token.hasSuffix(">") { return true }
        let characters = Array(token)
        for marker in ["NNN", "NUMBER", "WORD", "SECTION", "XXX", "N"] {
            let markerCharacters = Array(marker)
            for start in 0...max(characters.count - markerCharacters.count, 0)
            where characters.count >= markerCharacters.count {
                guard Array(characters[start..<start + markerCharacters.count]) == markerCharacters
                else { continue }
                // The head must be the all-caps/hyphen lead-in the
                // grammar allows, and — for the bare `N` — the marker
                // must end on a word boundary, or `NAME` would read as a
                // placeholder.
                let head = characters[..<start]
                guard head.allSatisfy({ ($0.isUppercase && $0.isLetter) || $0 == "-" }) else {
                    continue
                }
                let tail = characters[(start + markerCharacters.count)...]
                if marker == "N", let next = tail.first,
                    next.isLetter || next.isNumber || next == "_"
                { continue }
                guard
                    tail.allSatisfy({
                        $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-"
                    })
                else { continue }
                return true
            }
        }
        return false
    }

    /// First occurrence of each key wins.
    ///
    /// A key names a file and a token, so the second report of the same
    /// dangling identifier in the same file is the same defect seen
    /// twice. Reporting it twice would also make the ratchet
    /// count-sensitive, and a ratchet that moves when a sentence is
    /// duplicated is measuring the wrong thing.
    static func deduplicated(_ findings: [Rulebook.Finding]) -> [Rulebook.Finding] {
        var seen: Set<String> = []
        return findings.filter { seen.insert($0.key).inserted }
    }
}

// MARK: - Check 2: one definition site

extension Rulebook.Audit {
    func duplicates(in definitions: [Rulebook.Identifier: [Rulebook.Definition]]) -> [Rulebook.Finding] {
        var findings: [Rulebook.Finding] = []
        for identifier in definitions.keys.sorted() {
            // Heading sites only. A registry entry naming a
            // heading-defined identifier in the same file is indexing,
            // not redefinition; a registry entry in another file is the
            // hub check's business.
            let sites = (definitions[identifier] ?? []).filter { $0.form == .heading }
            guard sites.count >= 2 else { continue }
            let sanctioned = allowlist.aliases(mirroring: identifier)
            let effective = sites.filter { !sanctioned.contains($0.alias) }
            var perFile: [String: Int] = [:]
            for site in sites { perFile[site.alias, default: 0] += 1 }
            // A file defining the same identifier twice always fails: no
            // allowlist entry can sanction a document contradicting
            // itself.
            let duplicatedInOneFile = perFile.values.contains { $0 > 1 }
            guard effective.count > 1 || duplicatedInOneFile else { continue }
            let listed = sites.map { "\($0.alias):\($0.line)" }.joined(separator: ", ")
            findings.append(
                .init(
                    check: .duplicates, key: "[\(identifier)]",
                    message: "[\(identifier)] defined at \(sites.count) sites: \(listed)"))
        }
        return Self.deduplicated(findings)
    }
}

// MARK: - Check 3: cited artifacts exist

extension Rulebook.Audit {
    /// A path cited in aspirational tense carries no existence claim, and
    /// neither does one cited as forbidden. "Never `Research/audit.md`"
    /// is an instruction not to create a file, and failing it for the
    /// file's absence would invert the rule.
    static let aspirationalMarkers = [
        "aspirational", "pending", "future", "once it lands", "currently in draft",
        "missing as of", "not yet", "planned", "does not exist yet", "when it lands",
        "missing on disk", "re-locate or re-create",
        "never", "must not", "forbidden", "anti-pattern", "violation",
    ]

    static let pathExtensions = [".sh", ".py", ".md", ".yml", ".yaml", ".swift", ".tsv", ".json"]
    static let pathSkipCharacters: Set<Character> = ["{", "}", "<", ">", "*", "$", "…", " "]
    static let placeholderPathParts = ["XXX", "foo.", "bar.", "/tmp/"]

    /// First path segments that are workspace-anchored, and therefore
    /// verifiable. A relative path outside this set is a consumer-repo
    /// template (`.github/workflows/ci.yml`) that cannot be resolved from
    /// here, and is skipped rather than guessed at.
    static let anchorSegments: Set<String> = [
        "Scripts", "Research", "Skills", "Workspace", "Audits", "Blog",
        "Experiments", "Engagement", "Reflections", "handoffs",
        "swift-institute", "rule-institute", "rule-law", "rule-legal",
        "swift-law", "swift-nl-wetgever", "swift-us-nv-legislature",
    ]

    /// Bases a relative anchored path is tried against, after the citing
    /// file's own directory and its ancestors.
    static let searchBases = [
        "swift-institute", "swift-institute/Workspace",
        "swift-institute/Research", "swift-institute/Engagement",
        "swift-institute/swift-primitives",
        "swift-institute/swift-standards",
        "swift-institute/swift-foundations",
        "rule-institute", "rule-law",
    ]

    func artifacts() -> [Rulebook.Finding] {
        var findings: [Rulebook.Finding] = []
        for document in corpus.documents {
            // Every body line, fenced code included: a stale path in a
            // copy-pasteable command is worse than one in a sentence.
            for line in document.body {
                let lowered = line.text.lowercased()
                guard !Self.aspirationalMarkers.contains(where: lowered.contains) else { continue }
                for token in Self.backtickTokens(in: line.text) {
                    guard Self.looksLikePath(token), Self.isAnchored(token) else { continue }
                    guard !resolves(token, citedBy: document) else { continue }
                    findings.append(
                        .init(
                            check: .artifacts, key: "\(document.alias) \(token)",
                            message: "\(document.alias):\(line.number) cited path `\(token)` not "
                                + "found (annotate per [SKILL-LIFE-027] or re-point)"))
                }
            }
        }
        return Self.deduplicated(findings)
    }

    /// Backtick-quoted spans on a line.
    static func backtickTokens(in line: String) -> [String] {
        var tokens: [String] = []
        var current: String?
        for character in line {
            if character == "`" {
                if let open = current {
                    if !open.isEmpty { tokens.append(open.trimmingCharacters(in: .whitespaces)) }
                    current = nil
                } else {
                    current = ""
                }
            } else {
                current?.append(character)
            }
        }
        return tokens
    }

    /// Conservative by construction. The check exists to catch concrete
    /// stale paths, not to inventory every mention, so templates, globs,
    /// bare filenames, URLs, and scratch paths are all skipped.
    static func looksLikePath(_ token: String) -> Bool {
        guard token.contains("/") else { return false }
        guard !token.contains(where: pathSkipCharacters.contains) else { return false }
        guard !placeholderPathParts.contains(where: token.contains) else { return false }
        guard !token.hasPrefix("/tmp") else { return false }
        guard !token.contains("/.../") else { return false }
        if token.hasPrefix("/") && token.filter({ $0 == "/" }).count == 1 { return false }
        for prefix in ["http://", "https://", "git@", "-", "--"] where token.hasPrefix(prefix) {
            return false
        }
        var trimmed = Substring(token)
        while trimmed.last == "/" { trimmed = trimmed.dropLast() }
        let last = trimmed.components(separatedBy: "/").last ?? ""
        return pathExtensions.contains(where: last.hasSuffix)
    }

    static func isAnchored(_ token: String) -> Bool {
        if token.hasPrefix("/") || token.hasPrefix("~") { return true }
        let first = token.components(separatedBy: "/").first ?? token
        return anchorSegments.contains(first) || first.hasPrefix("swift-")
            || first.hasPrefix("rule-")
    }

    /// Whether an anchored token names something that exists.
    ///
    /// Absolute and `~` paths resolve directly. A relative anchored path
    /// is tried against the citing file's directory, each ancestor up to
    /// the developer root, the root itself, and the standard org/repo
    /// bases — because the rulebook is written from inside one repository
    /// about paths in several.
    func resolves(_ token: String, citedBy document: Rulebook.Document) -> Bool {
        if token.hasPrefix("~") {
            return FileManager.default.fileExists(atPath: NSString(string: token).expandingTildeInPath)
        }
        if token.hasPrefix("/") { return FileManager.default.fileExists(atPath: token) }
        let relative = token.hasPrefix("./") ? String(token.dropFirst(2)) : token
        var candidates = ["\(document.directory)/\(relative)", "\(developerRoot)/\(relative)"]
        var ancestor = document.directory
        while ancestor.hasPrefix("\(developerRoot)/") || ancestor == developerRoot {
            candidates.append("\(ancestor)/\(relative)")
            if ancestor == developerRoot { break }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        candidates.append(
            contentsOf: Self.searchBases.map { "\(developerRoot)/\($0)/\(relative)" })
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - Check 4: hub index reconciles

extension Rulebook.Audit {
    func hubIndex() -> [Rulebook.Finding] {
        var findings: [Rulebook.Finding] = []
        for skill in corpus.skills {
            guard let hub = skill.hub, !skill.companions.isEmpty else { continue }
            let hubText = hub.prose.map(\.text).joined(separator: "\n")
            for companion in skill.companions where !hubText.contains(companion.name) {
                findings.append(
                    .init(
                        check: .hubIndex, key: "\(skill.alias) \(companion.name)",
                        message: "\(skill.alias): companion \(companion.name) not named from "
                            + "SKILL.md"))
            }
            // A registry claim must be traceable in its own file's body.
            // Registry lines are excluded from that body: a range claim
            // never carries its member literals, so matching against the
            // header itself would make every registry vacuously correct.
            for document in skill.companions + [hub] {
                let body = document.prose
                    .filter { !Rulebook.Document.isRegistryHeader($0.text) }
                    .map(\.text)
                    .joined(separator: "\n")
                for identifier in Self.registered(in: document).sorted()
                where !body.contains(identifier.rawValue) {
                    findings.append(
                        .init(
                            check: .hubIndex, key: "\(skill.alias) registry [\(identifier)]",
                            message: "\(skill.alias): registry of \(document.name) claims "
                                + "[\(identifier)] but the body never carries it"))
                }
            }
        }
        return Self.deduplicated(findings)
    }
}
