import CI_Contract
import Foundation
import Testing

@testable import CI_Validation

/// The family-routing behaviour of `CI.Validation.Readme` that the
/// fixture corpus (readme-008/013/017/026) does not carry: exemption,
/// the unset family, the Family G profile paths, and Family F's implicit
/// README. The per-rule predicates themselves are exercised by the
/// shared harness over the corpus, and proved against the retired
/// implementation by the differential gate — these tests do not repeat
/// that.
@Suite
struct CIValidationReadmeTests {
    let validator = CI.Validation.Readme()

    @Suite
    struct Routing {
        let validator = CI.Validation.Readme()

        @Test func `a declared exemption emits nothing`() throws {
            let repository = TemporaryRepository()
            repository.write("readme:\n  exempt: vendored-upstream\n", to: ".github/metadata.yaml")
            repository.write("no H1 at all\n", to: "README.md")
            #expect(try validator.findings(in: repository.subject).isEmpty)
        }

        @Test func `an unset family is a finding not a pass`() throws {
            let repository = TemporaryRepository()
            repository.write("# Title\n", to: "README.md")
            let findings = try validator.findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["README-family-unset"])
        }

        @Test func `an unrecognised exemption falls through to unset`() throws {
            let repository = TemporaryRepository()
            repository.write("readme:\n  exempt: did-not-get-to-it\n", to: ".github/metadata.yaml")
            let findings = try validator.findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["README-family-unset"])
        }

        @Test func `a missing family E readme is a presence finding`() throws {
            let repository = TemporaryRepository()
            repository.write("readme:\n  family: E\n", to: ".github/metadata.yaml")
            let findings = try validator.findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["README-presence"])
            #expect(findings.first?.message.contains("family=E") == true)
        }

        @Test func `a missing family F readme is a namespace reservation`() throws {
            let repository = TemporaryRepository()
            repository.write("readme:\n  family: F\n", to: ".github/metadata.yaml")
            #expect(try validator.findings(in: repository.subject).isEmpty)
        }
    }

    @Suite
    struct `Family G Paths` {
        let validator = CI.Validation.Readme()

        @Test func `the org dot-github repo reads its profile at repo root`() throws {
            let repository = TemporaryRepository(repository: "swift-institute/.github")
            repository.write("readme:\n  family: G\n", to: ".github/metadata.yaml")
            repository.write("# Org\n\nProfile.\n", to: "profile/README.md")
            #expect(try validator.findings(in: repository.subject).isEmpty)
        }

        @Test func `any other repo reads the nested org-relative path`() throws {
            let repository = TemporaryRepository(repository: "swift-institute/other")
            repository.write("readme:\n  family: G\n", to: ".github/metadata.yaml")
            repository.write(
                "# Org\n\n## Installation\n\nforbidden\n", to: ".github/profile/README.md")
            let findings = try validator.findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["README-116"])
        }
    }

    @Suite
    struct Registry {
        @Test func `the registry serves this validator for the retired script`() {
            let validator = CI.Validation.Registry.validator(
                replacing: ".github/scripts/validate-readme.py")
            #expect(validator is CI.Validation.Readme)
        }

        @Test func `every corpus directory resolves to a registered rule`() {
            for directory in ["readme-008", "readme-013", "readme-017", "readme-026"] {
                #expect(CI.Validation.Registry.rule(forCorpusDirectory: directory) != nil)
            }
        }
    }
}
