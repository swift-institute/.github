import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// Publication hygiene for a public skill corpus — the seven
    /// `skill-*` rules.
    ///
    /// Checks mechanical, objective facts about skill files *as
    /// published artifacts*, and deliberately nothing about the writing:
    /// no length ceiling, no line cap, no required section, no opinion
    /// about tone or structure. Skills carry judgment rather than
    /// prescription; the only things worth gating are the facts that
    /// decide whether a skill loads at all and whether it is safe to
    /// have published.
    ///
    /// The predecessor gated on a description character ceiling no skill
    /// in the corpus could meet, so it was red from its first run. A gate
    /// nobody can pass teaches contributors to read red as normal, which
    /// is worse than no gate.
    ///
    /// Scope, by rule:
    ///
    /// - `skill-corpus-empty` — the whole repository, once. Fails closed:
    ///   a corpus that silently moved or vanished must not read as a
    ///   clean scan.
    /// - `skill-frontmatter`, `skill-identity` — every `<dir>/SKILL.md`.
    /// - `skill-links`, `skill-machine-path`, `skill-internal-rule-id`,
    ///   `skill-unsanctioned-reference` — every `.md` file in the
    ///   repository.
    ///
    /// Layout-agnostic: skills are found by locating `SKILL.md` at any
    /// depth, so a repository whose skills sit at the root and one that
    /// nests them under `Skills/` both work with no configured path.
    ///
    /// Ported from `.github/scripts/validate-skill-hygiene.py` (C9 of the
    /// F16 port), measured against it over the fixture corpus and the
    /// live `swift-institute/Skills` tree.
    public struct SkillHygiene: Validator {
        public static let corpusEmpty: Rule = "skill-corpus-empty"
        public static let frontmatter: Rule = "skill-frontmatter"
        public static let identity: Rule = "skill-identity"
        public static let links: Rule = "skill-links"
        public static let machinePath: Rule = "skill-machine-path"
        public static let internalRuleID: Rule = "skill-internal-rule-id"
        public static let unsanctionedReference: Rule = "skill-unsanctioned-reference"

        public let rules: [Rule] = [
            corpusEmpty, frontmatter, identity, links,
            machinePath, internalRuleID, unsanctionedReference,
        ]

        public let retiredScript: String? = ".github/scripts/validate-skill-hygiene.py"

        /// Where a scanned repository declares the cross-repository
        /// references it has already sanctioned.
        ///
        /// Lives in the **scanned** repository, not beside the validator,
        /// so the entry and the mention it covers land in the same pull
        /// request — the whole point is that the person adding the
        /// mention is the one who records it.
        public static let sanctionedReferences = ".github/sanctioned-references"

        /// Root of the `swift-institute/.github` checkout that carries
        /// the orgs manifest, when one is available.
        ///
        /// The retired script resolved the manifest relative to its own
        /// file, which a compiled binary cannot do: the executable is
        /// built from `Tools/institute-ci` and shipped through a cache
        /// entry, nowhere near `.github/actions/read-orgs/orgs.yaml`. So
        /// the location is an input, defaulting to the environment
        /// variable the workflow sets.
        ///
        /// Absence narrows the check exactly as the retired script's
        /// bare `except` did: the watch set then holds only owners named
        /// by the scanned repository's own sanctioned file. It never
        /// widens silently.
        public let supportRoot: String?

        public init(supportRoot: String? = ProcessInfo.processInfo.environment["INSTITUTE_CI_SUPPORT_ROOT"]) {
            self.supportRoot = supportRoot
        }

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let tree = try Tree(root: subject.root)
            var findings: [Finding] = []

            let skillFiles = tree.files(named: "SKILL.md")
            guard !skillFiles.isEmpty else {
                // Fail closed. If the corpus moved or the clone is wrong,
                // a silent zero is indistinguishable from a clean scan.
                return [
                    Finding(
                        repository: subject.repository, rule: Self.corpusEmpty,
                        message: "no SKILL.md found anywhere in the repository; "
                            + "the scan covered nothing and cannot be read as a pass")
                ]
            }

            // An owner already named on the sanctioned list joins the
            // watch set, so sanctioning `Internal/Skills` is what makes a
            // later `Internal/<anything>` visible to this check.
            let sanctioned = sanctionedList(in: tree)
            let watched = instituteOrganizations().union(
                sanctioned.compactMap { token in
                    token.contains("/") ? String(token.prefix(while: { $0 != "/" })) : nil
                })

            for path in skillFiles {
                findings += Skill(path: path, in: tree).findings(for: subject)
            }

            for path in tree.files(withExtension: ".md") {
                guard let text = tree.text(at: path) else {
                    // SKILL.md files are already reported above; report
                    // any other file once.
                    if (path as NSString).lastPathComponent != "SKILL.md" {
                        findings.append(
                            Finding(
                                repository: subject.repository, rule: Self.frontmatter,
                                message: "\(tree.relative(path)): not valid UTF-8"))
                    }
                    continue
                }
                let prose = Prose(path: path, text: text, in: tree)
                findings += prose.linkFindings(for: subject)
                findings += prose.proseFindings(for: subject)
                findings += prose.referenceFindings(
                    for: subject, sanctioned: sanctioned, watched: watched)
            }

            return findings
        }

        /// The scanned repository's sanctioned-reference list: one
        /// `owner/name` per line, `#` introduces a comment. A missing
        /// file is an empty list, so every watched reference is reported
        /// rather than skipped.
        func sanctionedList(in tree: Tree) -> Set<String> {
            guard let text = tree.text(at: tree.path(Self.sanctionedReferences)) else { return [] }
            var out: Set<String> = []
            for line in Self.lines(of: text) {
                let entry = line.prefix(while: { $0 != "#" })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !entry.isEmpty { out.insert(entry) }
            }
            return out
        }

        /// Org names from the checked-in manifest under `supportRoot`.
        ///
        /// Every name in the manifest today is already `swift-`
        /// prefixed, so it is matched by `Prose.instituteNamespace`
        /// regardless — the manifest widens the watch set only if an org
        /// outside that shape is ever added. Kept because that is the
        /// retired script's behaviour and dropping it would be a silent
        /// narrowing of a published control.
        func instituteOrganizations() -> Set<String> {
            guard let supportRoot else { return [] }
            let path = supportRoot + "/.github/actions/read-orgs/orgs.yaml"
            guard let data = FileManager.default.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8),
                  let node = try? CI.Workflow.YAML.Parser.parse(text),
                  let entries = node.sequence
            else { return [] }
            return Set(
                entries.compactMap { entry in
                    guard let name = entry["name"]?.text, !name.isEmpty else { return nil }
                    return name
                })
        }
    }
}
