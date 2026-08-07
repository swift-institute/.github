import CI_Contract
import Foundation

extension CI.Validation.SkillHygiene {
    /// The regular expressions the seven rules are written in, and the
    /// one place they are compiled.
    ///
    /// They are kept as patterns rather than rewritten as hand-parsed
    /// predicates on purpose. Each one is a *published* control whose
    /// exact reach people reason about when they decide whether a
    /// mention is sanctioned or a citation is internal; transcribing
    /// them into bespoke scanning code would change the reach in ways no
    /// reviewer could see. Their retired spellings are reproduced
    /// verbatim, and the differential gate is what proves the engines
    /// agree.
    struct Pattern: Sendable {
        private let expression: NSRegularExpression

        init(_ pattern: String, options: NSRegularExpression.Options = []) {
            // A literal pattern that does not compile is a programming
            // error, not a runtime condition: there is no input that
            // makes it compile later.
            expression = try! NSRegularExpression(pattern: pattern, options: options)
        }

        /// One match: the whole match, its capture groups, and where it
        /// starts.
        struct Match {
            let range: Range<String.Index>
            let groups: [String?]

            var whole: String { groups[0] ?? "" }
        }

        func firstMatch(in text: String) -> Match? {
            matches(in: text).first
        }

        /// Every non-overlapping match, left to right — `finditer`.
        func matches(in text: String) -> [Match] {
            let string = text as NSString
            return expression
                .matches(in: text, range: NSRange(location: 0, length: string.length))
                .compactMap { result in
                    guard let range = Range(result.range, in: text) else { return nil }
                    let groups = (0..<result.numberOfRanges).map { index -> String? in
                        let group = result.range(at: index)
                        return group.location == NSNotFound ? nil : string.substring(with: group)
                    }
                    return Match(range: range, groups: groups)
                }
        }
    }
}

extension CI.Validation.SkillHygiene.Pattern {
    /// The closing `---` of a frontmatter block.
    static let frontmatterTerminator = Self(#"^---\s*$"#, options: [.anchorsMatchLines])

    /// Maintainer home directories.
    ///
    /// `/Users/runner` and `/home/runner` are the shared GitHub-hosted
    /// runner paths — generic infrastructure, not anyone's machine — so
    /// they are excluded rather than reported.
    static let machinePath = Self(
        #"(?<![A-Za-z0-9_])(?:/Users/|/home/)(?!runner(?:[/\s]|$))[A-Za-z0-9._-]+/"#
            + #"|[A-Za-z]:\\Users\\[A-Za-z0-9._-]+\\"#)

    /// Internal rule-ID citations.
    ///
    /// The curated first segment is what separates an internal ID from
    /// an external standards citation such as `[RFC-7231]` or
    /// `[ISO-8601]`, which are legitimate in public prose.
    static let internalRuleID = Self(
        #"\[(?:README|MEM|DOC|API|MOD|PRIM|IMPL|PLAT|ARCH|TEST|SWIFT-TEST|BENCH|"#
            + #"INST-TEST|PATTERN|GH-REPO|SKILL|RES|EXP|BLOG|REFL|AUDIT|CONV|IDX|LEG|"#
            + #"NL-WET|RL|COPY|SEM|INFRA|CI|SOC|SUPER|HANDOFF|COLLAB|GIT|FREVIEW|SAVE|"#
            + #"RELEASE|META|PROMOTE|VERIFICATION|SKILL-CREATE|SKILL-LIFE)"#
            + #"(?:-[A-Z][A-Z0-9]*)*-[0-9]+[a-z]?\]"#)

    /// Inline markdown links: `[text](target)`.
    ///
    /// Reference-style links are not covered; the corpus uses none, and
    /// a check that silently half-covers a syntax is worse than one
    /// whose scope is stated.
    static let markdownLink = Self(#"\[[^\]]*\]\(\s*([^)\s]+)(?:\s+["'][^"']*["'])?\s*\)"#)

    /// `owner/name`, both GitHub-identifier shaped.
    ///
    /// The name may lead with a dot so that `swift-institute/.github` is
    /// seen. Trailing punctuation is trimmed afterwards rather than
    /// excluded here: prose ends references with a full stop, and a
    /// pattern that swallows it reports a token that can never match a
    /// list entry — a check that fires on correctly sanctioned text is
    /// worse than one that misses, because it teaches people the list
    /// does not work.
    static let reference = Self(
        #"(?<![A-Za-z0-9._/-])([A-Za-z][A-Za-z0-9._-]*)/(\.?[A-Za-z][A-Za-z0-9._-]*)"#)

    /// Namespaces the Institute owns, by shape rather than by
    /// enumeration.
    ///
    /// The orgs manifest lists 17, but that is a bot-convergence scope
    /// authored for nightly settings sweeps, not a namespace watch list
    /// — inheriting it left 42 of the fleet's 59 org namespaces
    /// unwatched. 54 of those 59 match this shape.
    ///
    /// By shape and not by list for a specific reason: the remaining
    /// five are unrelated ventures and a personal account, and a public
    /// file enumerating them would be the disclosure it is meant to
    /// guard against. That is the same bind as checking in a list of
    /// private repositories, and it is not closeable — you cannot watch
    /// for a name you are unwilling to write down.
    static let instituteNamespace = Self(#"^(?:swift|rule)-[a-z0-9-]+$"#)
}
