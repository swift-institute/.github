import CI_Contract
import Foundation
import Testing

@testable import CI_Validation

/// `skill-*` — publication hygiene for a public skill corpus.
///
/// The fixture ladder under `.github/scripts/tests/fixtures/skill-*/` is
/// the shared corpus and is exercised by the harness suite; what is here
/// is what the corpus cannot reach: the parity-critical helpers whose
/// behaviour the differential gate depends on but never isolates, and the
/// controls that must be able to fail.
@Suite
struct CIValidationSkillHygieneTests {
    static let validator = CI.Validation.SkillHygiene(supportRoot: nil)

    static func findings(in repository: borrowing TemporaryRepository) -> [CI.Validation.Finding] {
        (try? validator.findings(in: repository.subject)) ?? []
    }

    @Suite
    struct Unit {
        typealias Subject = CI.Validation.SkillHygiene

        @Test func `an absent corpus fails closed rather than reading as clean`() {
            let repository = TemporaryRepository()
            repository.write("# no skills here\n", to: "README.md")
            let findings = CIValidationSkillHygieneTests.findings(in: repository)
            #expect(findings.count == 1)
            #expect(findings.first?.rule == Subject.corpusEmpty)
        }

        @Test func `a frontmatter block ends at the first closing marker`() {
            // The block keeps the newline that follows the opening
            // marker — the retired reader sliced from index 3, and the
            // YAML parser is indifferent to a leading blank line.
            let block = Subject.Skill.frontmatterBlock(of: "---\nname: a\n---\n\n# Body\n")
            #expect(block == "\nname: a\n")
        }

        @Test func `text with no leading marker has no frontmatter`() {
            #expect(Subject.Skill.frontmatterBlock(of: "# Body\n") == nil)
        }

        @Test func `an unterminated block is absent, not empty`() {
            #expect(Subject.Skill.frontmatterBlock(of: "---\nname: a\n") == nil)
        }

        /// Line numbers appear in the finding messages the differential
        /// gate compares byte for byte, so the boundaries Python splits
        /// on are reproduced rather than approximated.
        @Test func `line splitting matches Python's splitlines`() {
            #expect(Subject.lines(of: "a\nb\r\nc\rd\u{2028}e") == ["a", "b", "c", "d", "e"])
            #expect(Subject.lines(of: "a\n") == ["a"])
            #expect(Subject.lines(of: "") == [])
        }

        @Test func `percent escapes decode, malformed ones are left alone`() {
            #expect(Subject.Prose.percentDecoded("a%20b.md") == "a b.md")
            #expect(Subject.Prose.percentDecoded("a%zzb.md") == "a%zzb.md")
            #expect(Subject.Prose.percentDecoded("plain.md") == "plain.md")
        }

        /// The runner's own home directories are shared infrastructure,
        /// not anyone's machine.
        @Test func `runner paths are not machine paths`() {
            #expect(Subject.Pattern.machinePath.firstMatch(in: "/home/runner/work/x") == nil)
            #expect(Subject.Pattern.machinePath.firstMatch(in: "/Users/someone/dev/") != nil)
        }

        /// The curated first segment is what separates an internal ID
        /// from a legitimate external standards citation.
        @Test func `external standards citations are not internal rule IDs`() {
            #expect(Subject.Pattern.internalRuleID.firstMatch(in: "see [RFC-7231]") == nil)
            #expect(Subject.Pattern.internalRuleID.firstMatch(in: "see [ISO-8601]") == nil)
            #expect(Subject.Pattern.internalRuleID.firstMatch(in: "see [CI-105]") != nil)
        }

        @Test func `institute namespaces are recognised by shape`() {
            #expect(Subject.Pattern.instituteNamespace.firstMatch(in: "swift-primitives") != nil)
            #expect(Subject.Pattern.instituteNamespace.firstMatch(in: "rule-institute") != nil)
            #expect(Subject.Pattern.instituteNamespace.firstMatch(in: "actions") == nil)
        }
    }

    /// Each rule's positive control: a shape that MUST produce a finding.
    /// A validator that silently stopped firing passes every clean
    /// scenario, which is how four gates in this repository were inert.
    @Suite
    struct Control {
        typealias Subject = CI.Validation.SkillHygiene

        static func rules(_ repository: borrowing TemporaryRepository) -> Set<CI.Validation.Rule> {
            Set(CIValidationSkillHygieneTests.findings(in: repository).map(\.rule))
        }

        @Test func `a skill whose name disagrees with its directory is reported`() {
            let repository = TemporaryRepository()
            repository.write("---\nname: beta\ndescription: d\n---\n", to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.identity))
        }

        @Test func `a skill with no description is reported`() {
            let repository = TemporaryRepository()
            repository.write("---\nname: alpha\n---\n", to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.identity))
        }

        @Test func `a skill with no frontmatter is reported`() {
            let repository = TemporaryRepository()
            repository.write("# Alpha\n", to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.frontmatter))
        }

        @Test func `a link that resolves to nothing is reported`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\n[gone](companion.md)\n",
                to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.links))
        }

        @Test func `a resolving link is silent`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\n[here](companion.md)\n",
                to: "alpha/SKILL.md")
            repository.write("# Companion\n", to: "alpha/companion.md")
            #expect(!Self.rules(repository).contains(Subject.links))
        }

        @Test func `a maintainer home directory in a public file is reported`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\nsee /Users/someone/dev/x\n",
                to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.machinePath))
        }

        @Test func `an internal rule ID in published prose is reported`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\nper [CI-105] this fires\n",
                to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.internalRuleID))
        }

        /// The predicate asks only whether the reference is *new* — a
        /// person decides at authoring time, in the pull request that
        /// introduces it.
        @Test func `an unsanctioned reference in a watched namespace is reported`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\nsee swift-primitives/thing\n",
                to: "alpha/SKILL.md")
            #expect(Self.rules(repository).contains(Subject.unsanctionedReference))
        }

        @Test func `a sanctioned reference is silent`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\nsee swift-primitives/thing\n",
                to: "alpha/SKILL.md")
            repository.write("swift-primitives/thing\n", to: ".github/sanctioned-references")
            #expect(!Self.rules(repository).contains(Subject.unsanctionedReference))
        }

        /// Prose ends references with a full stop; a check that fires on
        /// correctly sanctioned text teaches people the list does not
        /// work.
        @Test func `trailing punctuation does not defeat the sanctioned list`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\nsee swift-primitives/thing.\n",
                to: "alpha/SKILL.md")
            repository.write("swift-primitives/thing\n", to: ".github/sanctioned-references")
            #expect(!Self.rules(repository).contains(Subject.unsanctionedReference))
        }

        /// Sanctioning `Internal/Skills` is what makes a later
        /// `Internal/<anything>` visible to this check.
        @Test func `a sanctioned owner joins the watch set`() {
            let repository = TemporaryRepository()
            repository.write(
                "---\nname: alpha\ndescription: d\n---\n\nsee Internal/Other\n",
                to: "alpha/SKILL.md")
            repository.write("Internal/Skills\n", to: ".github/sanctioned-references")
            #expect(Self.rules(repository).contains(Subject.unsanctionedReference))
        }
    }
}
