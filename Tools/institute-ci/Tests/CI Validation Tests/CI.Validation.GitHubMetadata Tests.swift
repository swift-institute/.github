import CI_Contract
import Foundation
import Testing

@testable import CI_Validation

/// `[GH-REPO-METADATA]` — the schema validation of `.github/metadata.yaml`.
///
/// Expectations here are byte-for-byte the retired
/// `validate-github-metadata.py`'s output over the same bytes and the
/// committed `metadata-schema.json` (jsonschema 4.25.1, PyYAML 6.0.3),
/// recorded by the port's local differential before the script was
/// deleted. The message text is `jsonschema`'s, deliberately.
@Suite("CI.Validation.GitHubMetadata")
struct GitHubMetadataTests {
    /// The checkout's own schema, resolved from this file's location.
    var validator: CI.Validation.GitHubMetadata {
        CI.Validation.GitHubMetadata(
            schema: RepositoryUnderTest.root + "/metadata-schema.json")
    }

    func findings(metadata: String?) throws -> [CI.Validation.Finding] {
        let repository = TemporaryRepository()
        if let metadata { repository.write(metadata, to: ".github/metadata.yaml") }
        return try validator.findings(in: repository.subject)
    }

    @Test("a conformant file has no findings")
    func conformant() throws {
        let findings = try findings(
            metadata: """
                description: A fine package
                topics:
                  - parsing
                  - primitives
                homepage: https://swift-institute.org
                readme:
                  family: E
                """)
        #expect(findings.isEmpty)
    }

    @Test("an absent file is metadata-missing, an empty file is allowed")
    func absence() throws {
        let missing = try findings(metadata: nil)
        #expect(missing.map(\.rule) == ["metadata-missing"])
        #expect(try findings(metadata: "").isEmpty)
    }

    @Test("a non-mapping document is metadata-shape, in Python's words")
    func shape() throws {
        let findings = try findings(metadata: "- just\n- a list\n")
        #expect(findings.map(\.rule) == ["metadata-shape"])
        #expect(findings[0].message.hasSuffix("top-level value must be a mapping; got list"))
    }

    @Test("rules derive from the error path and messages match jsonschema")
    func schemaFindings() throws {
        let findings = try findings(
            metadata: """
                description: ""
                topics:
                  - Parsing
                  - parsing
                  - parsing
                homepage: 42
                readme:
                  family: B
                  exempt: vendored-upstream
                extra: true
                sidebar:
                  showReleases: yes
                  bogus: 1
                settings:
                  hasWikiEnabled: "yes"
                """)
        #expect(
            findings.map { "\($0.rule)\t\($0.message)" } == [
                "GH-REPO-021\t/: Additional properties are not allowed ('extra' was unexpected)",
                "GH-REPO-011\tdescription: '' should be non-empty",
                "GH-REPO-030-or-031\thomepage: 42 is not of type 'string'",
                "README-family\treadme: {'family': 'B', 'exempt': 'vendored-upstream'}"
                    + " is not valid under any of the given schemas",
                "README-family\treadme/family: 'B' is not one of ['A', 'C', 'E', 'F', 'G']",
                "GH-REPO-021\tsettings/hasWikiEnabled: 'yes' is not of type 'boolean'",
                "GH-REPO-021\tsidebar: Additional properties are not allowed ('bogus' was unexpected)",
                "GH-REPO-021-or-022\ttopics: ['Parsing', 'parsing', 'parsing']"
                    + " has non-unique elements",
                "GH-REPO-021-or-022\ttopics/0: 'Parsing' does not match '^[a-z][a-z0-9-]{0,49}$'",
            ])
    }

    @Test("a readme block with neither family nor exempt fails its oneOf")
    func readmeUnset() throws {
        let findings = try findings(metadata: "readme: {}\ntopics: [one]\n")
        #expect(
            findings.map { "\($0.rule)\t\($0.message)" } == [
                "README-family\treadme: {} is not valid under any of the given schemas",
                "GH-REPO-021-or-022\ttopics: ['one'] is too short",
            ])
    }

    @Test("messages truncate at jsonschema's 200 characters")
    func truncation() throws {
        let findings = try findings(
            metadata: "description: \(String(repeating: "x", count: 351))\n")
        #expect(findings.map(\.rule) == ["GH-REPO-011"])
        // "description: " + repr opening quote + 199 of the 351 x's.
        #expect(findings[0].message.count == 13 + 200)
    }

    @Test("a missing schema is a defect, not a finding")
    func missingSchema() {
        let repository = TemporaryRepository()
        repository.write("description: fine\n", to: ".github/metadata.yaml")
        let absent = CI.Validation.GitHubMetadata(
            schema: repository.path("no-such-schema.json"))
        #expect(throws: CI.Validation.EnvironmentDefect.self) {
            try absent.findings(in: repository.subject)
        }
    }
}
