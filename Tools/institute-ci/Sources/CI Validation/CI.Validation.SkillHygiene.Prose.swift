import CI_Contract
import Foundation

extension CI.Validation.SkillHygiene {
    /// One markdown file, asked the four questions that apply to
    /// published prose regardless of whether it is a skill: do its links
    /// resolve, does it leak a machine path, does it cite an internal
    /// rule ID, and does it name a cross-repository reference nobody has
    /// sanctioned.
    struct Prose {
        private typealias Rules = CI.Validation.SkillHygiene

        let path: String
        let text: String
        let tree: Tree

        init(path: String, text: String, in tree: Tree) {
            self.path = path
            self.text = text
            self.tree = tree
        }

        private var relative: String { tree.relative(path) }

        private func finding(
            _ rule: CI.Validation.Rule, _ subject: CI.Validation.Subject, _ message: String
        ) -> CI.Validation.Finding {
            CI.Validation.Finding(repository: subject.repository, rule: rule, message: message)
        }

        /// `skill-links` — every relative markdown link must resolve to a
        /// file in the repository.
        ///
        /// Progressive disclosure means companion documents carry real
        /// content; a pointer that 404s silently removes what it was
        /// meant to disclose.
        func linkFindings(for subject: CI.Validation.Subject) -> [CI.Validation.Finding] {
            var findings: [CI.Validation.Finding] = []
            for match in Pattern.markdownLink.matches(in: text) {
                guard let target = match.groups[1] else { continue }
                if Self.skippedLinkPrefixes.contains(where: target.hasPrefix)
                    || target.contains("://")
                {
                    continue
                }
                let cleaned = Self.percentDecoded(String(target.prefix(while: { $0 != "#" })))
                    .trimmed
                if cleaned.isEmpty { continue }
                let resolved =
                    cleaned.hasPrefix("/")
                    ? tree.path(String(cleaned.drop(while: { $0 == "/" })))
                    : (path as NSString).deletingLastPathComponent + "/" + cleaned
                guard !tree.resolves(resolved) else { continue }
                findings.append(
                    finding(
                        Rules.links, subject,
                        "\(relative): link target '\(target)' does not resolve to a file "
                            + "in the repository"))
            }
            return findings
        }

        /// `skill-machine-path` and `skill-internal-rule-id`, both of
        /// which cite a line number and therefore run over lines.
        func proseFindings(for subject: CI.Validation.Subject) -> [CI.Validation.Finding] {
            var findings: [CI.Validation.Finding] = []
            for (offset, line) in CI.Validation.SkillHygiene.lines(of: text).enumerated() {
                let number = offset + 1
                for match in Pattern.machinePath.matches(in: line) {
                    findings.append(
                        finding(
                            Rules.machinePath, subject,
                            "\(relative):\(number): machine-local path '\(match.whole)' "
                                + "in a public file"))
                }
                for match in Pattern.internalRuleID.matches(in: line) {
                    findings.append(
                        finding(
                            Rules.internalRuleID, subject,
                            "\(relative):\(number): internal rule ID '\(match.whole)' "
                                + "in published prose; name the behaviour instead"))
                }
            }
            return findings
        }

        /// `skill-unsanctioned-reference` — every reference in a watched
        /// namespace must be on the scanned repository's sanctioned list.
        ///
        /// The predicate is narrower than the name suggests. It does not
        /// decide whether a mention leaks anything; that judgment is not
        /// mechanizable, because a public README may legitimately name a
        /// private repository's existence while disclosing its contents
        /// would be a leak, and no pattern separates those. What this
        /// asks is only *is this reference new?* A reference already on
        /// the list is silent; one that is not stops the build, so a
        /// person decides at authoring time, in the pull request that
        /// introduces it, with the intent in front of them.
        ///
        /// That matters because the alternative disposition was "human
        /// review", and on a fleet where one account authors and merges
        /// there is no moment at which such a review can block. A control
        /// nobody can exercise is not a slower control; it is an absent
        /// one wearing the label.
        ///
        /// Known gap, stated rather than papered over: a private
        /// repository in a namespace never seen before is not watched, so
        /// its first mention is missed. Closing that would need a live
        /// list of private repositories, which cannot be checked into a
        /// public repository without being the disclosure it guards
        /// against.
        func referenceFindings(
            for subject: CI.Validation.Subject,
            sanctioned: Set<String>,
            watched: Set<String>
        ) -> [CI.Validation.Finding] {
            var findings: [CI.Validation.Finding] = []
            var seen: Set<String> = []
            for (offset, line) in CI.Validation.SkillHygiene.lines(of: text).enumerated() {
                let number = offset + 1
                for match in Pattern.reference.matches(in: line) {
                    guard let owner = match.groups[1], let captured = match.groups[2] else {
                        continue
                    }
                    guard watched.contains(owner)
                        || Pattern.instituteNamespace.firstMatch(in: owner) != nil
                    else { continue }
                    let name = String(
                        captured.reversed()
                            .drop(while: { Self.trailingPunctuation.contains($0) })
                            .reversed())
                    if name.isEmpty || name == "." { continue }
                    let token = "\(owner)/\(name)"
                    if sanctioned.contains(token) || seen.contains(token) { continue }
                    seen.insert(token)
                    findings.append(
                        finding(
                            Rules.unsanctionedReference, subject,
                            "\(relative):\(number): '\(token)' is not in "
                                + "\(CI.Validation.SkillHygiene.sanctionedReferences). "
                                + "If publishing it is intended, add it there in this change; "
                                + "this check asks only whether the reference is new, not "
                                + "whether it discloses anything"))
                }
            }
            return findings
        }

        static let skippedLinkPrefixes = ["http://", "https://", "mailto:", "tel:", "#", "<"]
        static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "-", "_"]

        /// `urllib.parse.unquote` over the ASCII subset markdown link
        /// targets use: `%XX` becomes its byte, and a malformed escape is
        /// left alone.
        static func percentDecoded(_ target: String) -> String {
            guard target.contains("%") else { return target }
            var bytes: [UInt8] = []
            var characters = Array(target.utf8)
            var index = 0
            while index < characters.count {
                if characters[index] == UInt8(ascii: "%"), index + 2 < characters.count,
                   let high = Self.hex(characters[index + 1]),
                   let low = Self.hex(characters[index + 2])
                {
                    bytes.append(high << 4 | low)
                    index += 3
                } else {
                    bytes.append(characters[index])
                    index += 1
                }
            }
            characters = bytes
            return String(decoding: characters, as: UTF8.self)
        }

        private static func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
            default: nil
            }
        }
    }
}
