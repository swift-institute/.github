import CI_Contract
import Foundation

extension CI.Validation {
    /// `[CI-117]` — a self-referential composite-action `uses:` must be
    /// identity-pinned to a full 40-hex commit SHA.
    ///
    /// Programme corrigendum §11.1 (`swift-institute/.github#286`, ruled
    /// R4/R4a/R4b) places Institute composite actions —
    /// `uses: <org>/<repo>/.github/actions/<name>@<ref>` — in the
    /// **identity-pinned** class. A branch, a short SHA, and a tag all
    /// fire.
    ///
    /// **This is the opposite of `[CI-030]`/`REPO-ACTIONS-004`**, which
    /// require intra-Institute *reusable workflows*
    /// (`…/.github/workflows/<file>.yml@<ref>`) to stay permanently on
    /// `@main`. Confusing the two classes in either direction is a hard
    /// stop. This validator matches the composite-action path segment
    /// and only that; it must not be widened to reusable-workflow
    /// `uses:` lines, and the retired suite's control for exactly that
    /// bleed is kept.
    ///
    /// **A line scan, not a YAML walk.** The rule is about the *ref
    /// text* at a *cited line number*, which a parsed document does not
    /// carry; a finding a reader cannot navigate to is a finding they
    /// will not act on.
    public struct CompositeActionPins: Validator {
        public static let rule: Rule = "CI-117"
        public static let exemptRule: Rule = "CI-117-EXEMPT"

        public let rules: [Rule] = [Self.rule, Self.exemptRule]
        public let retiredScript: String? = ".github/scripts/validate-composite-action-pins.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            var findings: [Finding] = []
            for path in try subject.workflowPaths() where path.hasSuffix(".yml") {
                let name = (path as NSString).lastPathComponent
                guard let data = FileManager.default.contents(atPath: path) else { continue }
                let text = String(decoding: data, as: UTF8.self)
                for site in Self.sites(in: text) {
                    let exemption = Self.exemption(workflow: name, action: site.action)
                    findings.append(
                        Finding(
                            repository: subject.repository,
                            rule: exemption == nil ? Self.rule : Self.exemptRule,
                            message: exemption.map {
                                Self.exemptMessage(workflow: name, site: site, reason: $0.reason)
                            } ?? Self.message(workflow: name, site: site)
                        )
                    )
                }
            }
            return findings
        }

        // MARK: - Scanning

        /// One unpinned self-referential composite-action reference.
        public struct Site: Sendable, Equatable {
            public let line: Int
            public let action: String
            public let reference: String
        }

        /// The path prefix that makes a `uses:` line this rule's business.
        ///
        /// Scoped to `swift-institute/.github`'s references to its *own*
        /// composite actions — the self-referential case the corrigendum
        /// named, because a repository cannot pin a reference to its own
        /// tree at authoring time. Third-party action pins are a
        /// different, already-covered class.
        static let referencePrefix = "swift-institute/.github/.github/actions/"

        static func sites(in text: String) -> [Site] {
            var sites: [Site] = []
            for (offset, line) in Self.lines(of: text).enumerated() {
                guard let site = Self.site(in: line, at: offset + 1) else { continue }
                sites.append(site)
            }
            return sites
        }

        /// `[- ]uses: <prefix><action>@<ref>[ # comment]`, or `nil`.
        ///
        /// A reference whose `<ref>` is already a full 40-character
        /// lowercase-hex SHA is not a site — it is the conforming shape.
        static func site(in line: Substring, at number: Int) -> Site? {
            var rest = line.drop { $0 == " " || $0 == "\t" }
            if rest.first == "-" {
                rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" }
            }
            guard rest.hasPrefix("uses:") else { return nil }
            rest = rest.dropFirst("uses:".count).drop { $0 == " " || $0 == "\t" }
            guard rest.hasPrefix(referencePrefix) else { return nil }
            rest = rest.dropFirst(referencePrefix.count)
            let action = rest.prefix {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
            }
            guard !action.isEmpty else { return nil }
            rest = rest.dropFirst(action.count)
            guard rest.first == "@" else { return nil }
            rest = rest.dropFirst()
            let reference = rest.prefix { !$0.isWhitespace }
            guard !reference.isEmpty else { return nil }
            // Anything after the reference must be whitespace, or
            // whitespace then a trailing `#` comment. A second token is
            // not a `uses:` line this rule recognises.
            let trailing = rest.dropFirst(reference.count).drop { $0.isWhitespace }
            guard trailing.isEmpty || trailing.first == "#" else { return nil }
            guard !Self.isIdentityPin(reference) else { return nil }
            return Site(line: number, action: String(action), reference: String(reference))
        }

        /// A full 40-character lowercase-hex commit SHA, and nothing
        /// looser. A short SHA is still a floating ref.
        static func isIdentityPin(_ reference: some StringProtocol) -> Bool {
            reference.count == 40
                && reference.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
        }

        /// Physical lines, with a trailing carriage return removed and a
        /// final empty line dropped — the line numbering a reader sees in
        /// an editor and in a diff.
        static func lines(of text: String) -> [Substring] {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.last?.isEmpty == true { lines.removeLast() }
            return lines.map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        }

        // MARK: - Exemptions

        /// A typed, reasoned exemption — owner, trigger, reason,
        /// retirement condition — recorded as data rather than as a
        /// wildcard.
        ///
        /// The site is an exact `(workflow file, action)` **pair, never a
        /// filename wildcard**: a *different* action gaining an unpinned
        /// reference in the same file must still fire, and the retired
        /// suite's control asserts exactly that.
        public struct Exemption: Sendable, Hashable {
            public let workflow: String
            public let action: String
            public let reason: String
        }

        /// `lint-validators-weekly.yml`'s two sites.
        ///
        /// Owner: lane 0B-01 holds that file in flight
        /// (`swift-institute/.github#295`) under the same programme;
        /// task 0A-04's resource-lane grant excludes it to avoid a
        /// two-lane write collision. Reason: cross-lane file ownership,
        /// not disagreement about the rule. **Retirement condition:**
        /// delete these two entries in the same change that next touches
        /// those lines under either lane — do not carry them forward once
        /// the file is free again.
        static let exemptions: [Exemption] = [
            Exemption(
                workflow: "lint-validators-weekly.yml",
                action: "read-orgs",
                reason: Self.laneReason
            ),
            Exemption(
                workflow: "lint-validators-weekly.yml",
                action: "upsert-tracking-issue",
                reason: Self.laneReason
            ),
        ]

        static let laneReason =
            "swift-institute/.github#286 resource-lane grant excludes this file; "
            + "owned in flight by lane 0B-01 (swift-institute/.github#295)"

        static func exemption(workflow: String, action: String) -> Exemption? {
            exemptions.first { $0.workflow == workflow && $0.action == action }
        }

        // MARK: - Messages

        static func message(workflow: String, site: Site) -> String {
            "\(workflow):\(site.line): \(referencePrefix)\(site.action)@\(site.reference) "
                + "is not identity-pinned — Institute composite actions (§2.11) pin to a "
                + "full 40-hex commit SHA, never a branch or tag. This is the "
                + "composite-action class, distinct from [CI-030]'s permanently-@main "
                + "reusable-workflow class — do not 'fix' this by exempting the site."
        }

        static func exemptMessage(workflow: String, site: Site, reason: String) -> String {
            "\(workflow):\(site.line): \(referencePrefix)\(site.action)@\(site.reference) "
                + "— exempt: \(reason)"
        }
    }
}
