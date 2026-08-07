import CI_Contract
import Foundation
import Testing

@testable import CI_Validation

/// `[GH-REPO-063]`.
///
/// The rule's corpus lives at `tests/schema-correspondence/`, OUTSIDE
/// the validator-fixture corpus — the retired script took three file
/// paths rather than a repository root, and its scenarios keep the
/// three files flat in one directory. The harness suite therefore does
/// not reach it; this suite runs those scenarios directly, plus the
/// live repository, plus the reading decisions the fixtures cannot
/// express.
@Suite
struct CIValidationSchemaCorrespondenceTests {
    /// This repository, located from the file rather than the working
    /// directory.
    static var repositoryRoot: String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.path
    }

    static func scenario(_ kind: String, _ name: String) -> CI.Validation.SchemaCorrespondence {
        let directory = "\(repositoryRoot)/.github/scripts/tests/schema-correspondence/\(kind)/\(name)"
        return .init(
            schemaFile: "\(directory)/metadata-schema.json",
            syncWorkflowFile: "\(directory)/sync-metadata.yml",
            readmeValidatorFile: "\(directory)/validate-readme.py")
    }

    static var subject: CI.Validation.Subject {
        .init(repository: "swift-institute/.github", root: repositoryRoot)
    }

    @Suite
    struct Corpus {
        /// The one pass scenario: zero findings.
        @Test func `pass slash consistent is clean`() throws {
            let findings = try CIValidationSchemaCorrespondenceTests
                .scenario("pass", "consistent")
                .findings(in: CIValidationSchemaCorrespondenceTests.subject)
            #expect(findings.isEmpty)
        }

        /// Every fail scenario must produce a finding — these are the
        /// positive controls; a rule that cannot fail is not a gate.
        @Test(arguments: [
            "constant-renamed",
            "readme-exempt-unhandled",
            "readme-family-unhandled",
            "settings-key-unread",
        ])
        func `each fail scenario fires`(name: String) throws {
            let findings = try CIValidationSchemaCorrespondenceTests
                .scenario("fail", name)
                .findings(in: CIValidationSchemaCorrespondenceTests.subject)
            #expect(!findings.isEmpty)
            #expect(findings.allSatisfy { $0.rule == "GH-REPO-063" })
        }

        /// A renamed constant is the "could not establish" class and
        /// must be reported as such, not as agreement — the exact
        /// failure the retired script's earlier draft had.
        @Test func `a renamed constant reads as a finding, not agreement`() throws {
            let findings = try CIValidationSchemaCorrespondenceTests
                .scenario("fail", "constant-renamed")
                .findings(in: CIValidationSchemaCorrespondenceTests.subject)
            #expect(findings.contains { $0.message.contains("has no module-level `EXEMPTIONS`") })
        }
    }

    @Suite
    struct Integration {
        /// The live repository's own correspondence, at the defaults the
        /// deployed caller uses.
        @Test func `the live schema corresponds with its consumers`() throws {
            let findings = try CI.Validation.SchemaCorrespondence()
                .findings(in: CIValidationSchemaCorrespondenceTests.subject)
            #expect(findings.isEmpty)
        }

        /// A missing input file is the exit-2 class, never a pass.
        @Test func `a missing schema is a defect, not a clean run`() {
            let validator = CI.Validation.SchemaCorrespondence(
                schemaFile: "/nonexistent/metadata-schema.json")
            #expect(throws: CI.Validation.EnvironmentDefect.self) {
                try validator.findings(in: CIValidationSchemaCorrespondenceTests.subject)
            }
        }
    }

    @Suite
    struct Unit {
        typealias Validator = CI.Validation.SchemaCorrespondence

        /// The consumer constants are read by name from module level
        /// only, and the last assignment wins — the `ast` semantics the
        /// retired script relied on.
        @Test func `module-level tuple extraction`() {
            let source = """
                \"\"\"doc\"\"\"
                EXEMPTIONS = ("a", 'b',)
                if True:
                    FAMILIES = ("indented", "never", "seen")
                FAMILIES = (
                    "A",  # kept
                    "B",
                )
                FAMILIES = ["A", "C"]
                """
            let constants = Validator.moduleLevelStringSequences(
                in: source, names: ["EXEMPTIONS", "FAMILIES"])
            #expect(constants["EXEMPTIONS"] == ["a", "b"])
            #expect(constants["FAMILIES"] == ["A", "C"])
        }

        /// A partially-literal sequence is rejected whole: half an
        /// answer is indistinguishable from agreement.
        @Test func `non-literal sequences read as not established`() {
            for expression in ["(\"a\", name)", "(f\"a\")", "\"bare\"", "(\"a\" + \"b\")"] {
                #expect(Validator.parseStringSequence(expression) == nil)
            }
            #expect(Validator.parseStringSequence("()") == [])
        }

        /// A renamed constant does not match by prefix: the fixture's
        /// `README_EXEMPTIONS` must not answer for `EXEMPTIONS`, and
        /// `EXEMPTIONS2` is a different name too.
        @Test func `identifier match is exact`() {
            let constants = Validator.moduleLevelStringSequences(
                in: "README_EXEMPTIONS = (\"x\",)\nEXEMPTIONS2 = (\"y\",)\n",
                names: ["EXEMPTIONS"])
            #expect(constants["EXEMPTIONS"] == .some(nil))
        }

        /// The `.settings.<key>` scan matches the retired regex
        /// `\\.settings\\.([A-Za-z][A-Za-z0-9]*)` — no underscores, and
        /// a key must start with a letter.
        @Test func `settings-key scan`() {
            let keys = Validator.settingsKeys(
                in: ".settings.alpha .settings.b2 .settings.snake_case .settings.9no x.settings.deep")
            #expect(keys == ["alpha", "b2", "snake", "deep"])
        }

        /// The list rendering is Python's `repr`, byte-for-byte — it
        /// appears inside messages the differential gate compared.
        @Test func `lists render as Python repr`() {
            #expect(Validator.list(["a", "b"]) == "['a', 'b']")
            #expect(Validator.list([]) == "[]")
        }
    }
}
