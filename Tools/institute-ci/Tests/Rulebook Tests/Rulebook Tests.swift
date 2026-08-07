import Testing

@testable import Rulebook

/// The canon guard, checked against the shapes the corpus actually
/// contains.
///
/// The corpus is data and is never written by a test. Everything that can
/// be asked of a `Document` or a `Corpus` is asked of values built in
/// memory, so the suite exercises the predicates rather than the
/// filesystem; the one check that genuinely needs a disk — artifact
/// resolution — is reached through its pure predicates instead.
extension Rulebook {
    @Suite
    struct Tests {
        static func corpus(_ files: [(alias: String, text: String)]) -> Rulebook.Corpus {
            .init(
                documents: files.map {
                    .init(path: "/corpus/\($0.alias)", alias: $0.alias, text: $0.text)
                },
                skills: [])
        }

        static func audit(_ corpus: Rulebook.Corpus) -> Rulebook.Audit {
            .init(
                corpus: corpus, baseline: .init(entries: []), allowlist: .init(entries: []),
                developerRoot: "/corpus")
        }

        /// The grammars: what an identifier is, and what a citation of one
        /// looks like.
        @Suite
        struct Unit {
            @Test func `a numeric identifier splits at its last number group`() throws {
                let parts = try #require(Rulebook.Identifier("API-NAME-001").parts)
                #expect(parts.family == "API-NAME")
                #expect(parts.number == 1)
                #expect(parts.suffix == "")
            }

            @Test func `a letter suffix is part of the identifier, not of the number`() throws {
                let parts = try #require(Rulebook.Identifier("PLAT-ARCH-008g").parts)
                #expect(parts.family == "PLAT-ARCH")
                #expect(parts.number == 8)
                #expect(parts.suffix == "g")
            }

            @Test func `a word-form identifier has no number to compare`() {
                #expect(Rulebook.Identifier("IMPL-INTENT").parts == nil)
                #expect(Rulebook.Identifier.isWord("IMPL-INTENT"))
                #expect(!Rulebook.Identifier.isWord("API-NAME-001"))
                #expect(Rulebook.Identifier.isNumeric("API-NAME-001"))
            }

            /// Lexicographic ordering of the raw text puts `X-10` before
            /// `X-9`, and a registry listed that way reads as corrupt.
            @Test func `ordering is numeric within a family`() {
                #expect(Rulebook.Identifier("X-9") < Rulebook.Identifier("X-10"))
            }

            @Test func `a range expands to its members at the start's width`() {
                #expect(
                    Rulebook.Identifier.range(from: "API-NAME-009", to: "API-NAME-011")
                        == ["API-NAME-009", "API-NAME-010", "API-NAME-011"])
            }

            @Test func `a single cite is recognised in both grammars`() {
                #expect(Rulebook.Citation.scan("see [API-NAME-001]").count == 1)
                #expect(Rulebook.Citation.scan("see [IMPL-INTENT]").count == 1)
                #expect(Rulebook.Citation.scan("see [lowercase-001]").isEmpty)
            }

            /// The defect that made this port's first volume run disagree
            /// with the retired engine on ten findings: `[per [RES-019]]` and
            /// `[[ALL-OK]]` are both real corpus shapes, and a scanner taking
            /// the outermost bracket reads `per [RES-019` — a token matching
            /// no grammar — and calls the file clean.
            @Test(arguments: ["## Survey [per [RES-019]]", "**PASS** (`[[ALL-OK]]`)"])
            func `the innermost bracket pair is the citation`(_ line: String) {
                #expect(Rulebook.Citation.scan(line).count == 1)
            }

            @Test func `a cross-bracket range yields both endpoints`() {
                guard case .crossRange(let start, let end) =
                    Rulebook.Citation.scan("[A-001]–[A-005]").first?.form
                else {
                    Issue.record("expected a cross range")
                    return
                }
                #expect(start == "A-001")
                #expect(end == "A-005")
            }

            /// Precedence, not just recognition: a cross-range's endpoints
            /// must not also be counted as two singles.
            @Test func `a cross range is not re-read as two singles`() {
                #expect(Rulebook.Citation.scan("[A-001] - [A-005]").count == 1)
            }

            @Test func `an in-bracket range completes the end from the start's family`() {
                guard case .inBracketRange(let start, let end) =
                    Rulebook.Citation.scan("[PATTERN-012–062]").first?.form
                else {
                    Issue.record("expected an in-bracket range")
                    return
                }
                #expect(start == "PATTERN-012")
                #expect(end == "PATTERN-062")
            }

            @Test func `a wildcard names its family`() {
                guard case .wildcard(let family) =
                    Rulebook.Citation.scan("the [MEM-COPY-*] family").first?.form
                else {
                    Issue.record("expected a wildcard")
                    return
                }
                #expect(family == "MEM-COPY")
            }

            @Test(arguments: [
                "Research/notes.md", "swift-institute/Skills/a.md", "/abs/path/x.yml", "~/x.md",
            ])
            func `an anchored path is a verifiable citation`(_ token: String) {
                #expect(Rulebook.Audit.looksLikePath(token))
                #expect(Rulebook.Audit.isAnchored(token))
            }

            /// `[SKILL-CREATE-005c]`: a counter recognising only the heading
            /// form silently undercounts every catalogue-form skill, and an
            /// undercount is worse than no count because it reads as
            /// evidence.
            @Test func `the census recognises both definition forms`() {
                #expect(Rulebook.Census.isHeadingRow("### [API-NAME-001]"))
                #expect(Rulebook.Census.isHeadingRow("## [API-NAME-001] Title"))
                #expect(!Rulebook.Census.isHeadingRow("# [API-NAME-001]"))
                #expect(Rulebook.Census.isTableRow("| [API-NAME-001] | statement |"))
                #expect(!Rulebook.Census.isTableRow("| API-NAME-001 | statement |"))
            }

            /// The key names a file and a token, not a line, so a baselined
            /// finding survives an edit above it. A ratchet that went red on
            /// every reflow would teach its readers to re-baseline
            /// reflexively.
            @Test func `the baseline key carries no line number`() {
                let finding = Rulebook.Finding(check: .citations, key: "a.md [A-002]", message: "a.md:9 …")
                #expect(finding.baselineEntry == "citations a.md [A-002]")
            }
        }

        /// The four checks, over corpora assembled in memory.
        @Suite
        struct Integration {
            @Test func `a dangling citation is reported and a resolved one is not`() {
                let corpus = Rulebook.Tests.corpus([("a.md", "### [A-001]\nSee [A-001] and [A-002].\n")])
                let findings = Rulebook.Tests.audit(corpus).run([.citations]).results[.citations] ?? []
                #expect(findings.count == 1)
                #expect(findings[0].message.contains("[A-002] unresolved"))
            }

            /// A supersession idiom on the line means the author knows the
            /// identifier is gone and is saying so on purpose.
            @Test func `a historical marker exempts the whole line`() {
                let corpus = Rulebook.Tests.corpus([
                    ("a.md", "### [A-001]\n[A-002] was retired; the slot stays burned.\n")
                ])
                #expect(Rulebook.Tests.audit(corpus).run([.citations]).results[.citations]?.isEmpty == true)
            }

            @Test func `template grammar is not a citation`() {
                let corpus = Rulebook.Tests.corpus([("a.md", "Use [PREFIX-001] or [FOO-NNN].\n")])
                #expect(Rulebook.Tests.audit(corpus).run([.citations]).results[.citations]?.isEmpty == true)
            }

            @Test func `two heading sites for one identifier is a duplicate`() {
                let corpus = Rulebook.Tests.corpus([
                    ("a.md", "### [A-001]\nx\n"), ("b.md", "### [A-001]\ny\n"),
                ])
                let findings = Rulebook.Tests.audit(corpus).run([.duplicates]).results[.duplicates] ?? []
                #expect(findings.count == 1)
                #expect(findings[0].message.contains("defined at 2 sites: a.md:1, b.md:1"))
            }

            /// A registry entry indexes; it does not redefine. Counting it as
            /// a second site would fail every catalogue-form skill.
            @Test func `a registry entry beside a heading is not a duplicate`() {
                let corpus = Rulebook.Tests.corpus([
                    ("a.md", "**Rules in this file:** [A-001]\n\n### [A-001]\nx\n")
                ])
                #expect(
                    Rulebook.Tests.audit(corpus).run([.duplicates]).results[.duplicates]?.isEmpty == true)
            }

            @Test func `an allowlisted mirror is sanctioned`() {
                let corpus = Rulebook.Tests.corpus([
                    ("a.md", "### [A-001]\nx\n"), ("b.md", "### [A-001]\ny\n"),
                ])
                let audit = Rulebook.Audit(
                    corpus: corpus, baseline: .init(entries: []),
                    allowlist: .init(entries: [
                        .init(identifier: "A-001", alias: "a.md"),
                        .init(identifier: "A-001", alias: "b.md"),
                    ]),
                    developerRoot: "/corpus")
                #expect(audit.run([.duplicates]).results[.duplicates]?.isEmpty == true)
            }

            @Test func `a registry range claim is expanded and reconciled`() {
                let hub = Rulebook.Document(
                    path: "/c/s/SKILL.md", alias: "s:SKILL.md",
                    text: "See companion.md.\n\n**Rules in this file:** [A-001]–[A-003]\n\n"
                        + "### [A-001]\nA-001, A-002 here.\n")
                let companion = Rulebook.Document(
                    path: "/c/s/companion.md", alias: "s:companion.md", text: "# Companion\n")
                let corpus = Rulebook.Corpus(
                    documents: [hub, companion],
                    skills: [.init(alias: "s", directory: "/c/s", members: [hub, companion])])
                let findings = Rulebook.Tests.audit(corpus).run([.hubIndex]).results[.hubIndex] ?? []
                #expect(findings.count == 1)
                #expect(findings[0].message.contains("claims [A-003]"))
            }

            @Test func `a companion the hub never names is reported`() {
                let hub = Rulebook.Document(path: "/c/s/SKILL.md", alias: "s:SKILL.md", text: "# Hub\n")
                let companion = Rulebook.Document(
                    path: "/c/s/other.md", alias: "s:other.md", text: "# Other\n")
                let corpus = Rulebook.Corpus(
                    documents: [hub, companion],
                    skills: [.init(alias: "s", directory: "/c/s", members: [hub, companion])])
                let findings = Rulebook.Tests.audit(corpus).run([.hubIndex]).results[.hubIndex] ?? []
                #expect(findings.count == 1)
                #expect(findings[0].message.contains("companion other.md not named from SKILL.md"))
            }

            @Test func `a baselined finding is not counted as new`() {
                let corpus = Rulebook.Tests.corpus([("a.md", "See [A-002].\n")])
                let audit = Rulebook.Audit(
                    corpus: corpus, baseline: .init(entries: ["citations a.md [A-002]"]),
                    allowlist: .init(entries: []), developerRoot: "/corpus")
                let report = audit.run([.citations])
                #expect(report.results[.citations]?.count == 1)
                #expect(report.freshCount == 0)
                #expect(report.isClean)
            }

            @Test func `the report renders the retired engine's lines`() {
                let corpus = Rulebook.Tests.corpus([("a.md", "See [A-002].\n")])
                let lines = Rulebook.Tests.audit(corpus).run([.citations]).lines(enforcing: false)
                #expect(lines.first == "check-canon[citations]: 1 finding(s)")
                #expect(lines.last?.hasSuffix("1 files, 0 defined ids [report-only]") == true)
            }
        }

        /// The boundaries, and the refusals that are not findings.
        @Suite
        struct `Edge Case` {
            /// Expansion is refused where arithmetic would be meaningless.
            /// Inventing members would turn one citation into dozens of
            /// phantom definitions.
            @Test(arguments: [
                (Rulebook.Identifier("A-001"), Rulebook.Identifier("B-003")),
                ("A-001a", "A-003"),
                ("A-005", "A-001"),
                ("A-001", "A-900"),
                ("IMPL-INTENT", "A-003"),
            ])
            func `an unexpandable range keeps only its endpoints`(
                _ start: Rulebook.Identifier, _ end: Rulebook.Identifier
            ) {
                #expect(Rulebook.Identifier.range(from: start, to: end) == [start, end])
            }

            /// A citation inside a fenced block is illustration, not a claim
            /// — and a heading inside one is not a definition.
            @Test func `fenced code defines nothing and claims nothing`() {
                let corpus = Rulebook.Tests.corpus([
                    ("a.md", "```\n### [A-001]\nsee [A-002]\n```\nSee [A-001].\n")
                ])
                let findings = Rulebook.Tests.audit(corpus).run([.citations]).results[.citations] ?? []
                #expect(findings.count == 1)
                #expect(findings[0].message.contains("[A-001] unresolved"))
            }

            /// Frontmatter carries changelog history that cites retired
            /// identifiers on purpose; scanning it would report the corpus's
            /// own memory as rot.
            @Test func `frontmatter is not scanned`() {
                let corpus = Rulebook.Tests.corpus([("a.md", "---\nhistory: dropped [A-002]\n---\nBody.\n")])
                #expect(Rulebook.Tests.audit(corpus).run([.citations]).results[.citations]?.isEmpty == true)
            }

            /// No allowlist entry can sanction a document contradicting
            /// itself.
            @Test func `a file defining an identifier twice always fails`() {
                let corpus = Rulebook.Tests.corpus([("a.md", "### [A-001]\nx\n\n### [A-001]\ny\n")])
                let audit = Rulebook.Audit(
                    corpus: corpus, baseline: .init(entries: []),
                    allowlist: .init(entries: [.init(identifier: "A-001", alias: "a.md")]),
                    developerRoot: "/corpus")
                #expect(audit.run([.duplicates]).results[.duplicates]?.count == 1)
            }

            @Test(arguments: [
                "https://example.com/a.md", "Research/*.md", "Research/{x}.md", "/tmp/x.md",
                "Research/foo.md", "/a.md", "Research/.../x.md", "notafile",
            ])
            func `templates, globs, URLs and scratch paths are not path citations`(_ token: String) {
                #expect(!Rulebook.Audit.looksLikePath(token))
            }

            /// A consumer-repo template cannot be resolved from here, so it
            /// is skipped rather than guessed at.
            @Test func `an unanchored relative path is not verifiable`() {
                #expect(Rulebook.Audit.looksLikePath(".github/workflows/ci.yml"))
                #expect(!Rulebook.Audit.isAnchored(".github/workflows/ci.yml"))
            }

            /// No roots is no measurement, not a count of zero.
            @Test func `an empty root set is a defect`() {
                #expect(throws: Rulebook.Census.Error.noRoots) {
                    _ = try Rulebook.Census.taken(over: [])
                }
            }
        }
    }
}
