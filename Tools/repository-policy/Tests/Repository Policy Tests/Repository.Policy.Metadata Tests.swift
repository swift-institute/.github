import Testing

@testable import Repository_Policy

@Suite
struct RepositoryPolicyMetadataTests {
    static let titles = Repository.Policy.Metadata.Draft.Titles(
        parsing: """
            # spec-titles.yaml
            rfc:
              '3986': 'Uniform Resource Identifier (URI) Generic Syntax'
            bcp:
              '47': 'Tags for Identifying Languages'
            iso:
              '8601': 'Date and time'
            iso-iec:
              '9945': 'Portable Operating System Interface (POSIX)'
            """)

    static func draft(_ target: String, packageDescription: String = "") throws
        -> Repository.Policy.Metadata.Draft
    {
        try .init(target: target, titles: titles, packageDescription: packageDescription)
    }

    @Suite
    struct Unit {
        @Test func `a numbered spec drafts from the title table`() throws {
            let draft = try RepositoryPolicyMetadataTests.draft("swift-ietf/swift-rfc-3986")
            #expect(draft.kind == .singleSpec)
            #expect(
                draft.metadata.description
                    == "Swift implementation of RFC 3986: "
                        + "Uniform Resource Identifier (URI) Generic Syntax.")
            #expect(draft.metadata.topics == ["standards", "rfc", "rfc-3986", "TODO-domain-tag"])
        }

        @Test func `an organization defaults repository asserts no homepage`() throws {
            // `homepage: ""` would tell sync-metadata to clear whatever
            // is there; the key is omitted instead.
            let draft = try RepositoryPolicyMetadataTests.draft("swift-institute/.github")
            #expect(draft.kind == .organizationDefaults)
            #expect(draft.metadata.homepage.isEmpty)
            let rendered = Repository.Policy.Metadata.Draft.Render(generatedOn: "2026-08-07")(draft)
            #expect(!rendered.contains("homepage"))
            #expect(rendered.contains("topics: []"))
        }

        @Test func `a primitive takes its own package description`() throws {
            let draft = try RepositoryPolicyMetadataTests.draft(
                "swift-primitives/swift-byte-primitives", packageDescription: "Byte primitives")
            #expect(draft.kind == .primitive)
            #expect(draft.metadata.description == "Byte primitives for Swift.")
        }

        @Test func `the rendered draft carries the review instruction`() throws {
            // What makes a draft a draft. Without it a heuristic seed
            // reads as an authored document.
            let rendered = Repository.Policy.Metadata.Draft.Render(generatedOn: "2026-08-07")(
                try RepositoryPolicyMetadataTests.draft("swift-ietf/swift-rfc-3986"))
            #expect(rendered.contains("# REVIEW BEFORE MERGE"))
            #expect(rendered.contains("# Detected class: L2-single-spec"))
            #expect(rendered.hasSuffix("\n"))
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `a joint spec is drafted as ISO slash IEC`() throws {
            // The one branch that consults the table twice: finding the
            // spec under `iso-iec` changes the authority *and* the topic
            // set, so the second lookup cannot be folded into the first.
            let draft = try RepositoryPolicyMetadataTests.draft("swift-iso/swift-iso-9945")
            #expect(draft.metadata.description.hasPrefix("Swift implementation of ISO/IEC 9945:"))
            #expect(draft.metadata.topics.contains("iso-iec"))
        }

        @Test func `a missing title becomes a visible TODO, not a silent gap`() throws {
            let draft = try RepositoryPolicyMetadataTests.draft("swift-iso/swift-iso-99999")
            #expect(draft.metadata.description.contains("TODO add title to spec-titles.yaml"))
        }

        @Test func `a spec named rather than numbered takes the named branch`() throws {
            let draft = try RepositoryPolicyMetadataTests.draft("swift-w3c/swift-w3c-webidl")
            #expect(draft.kind == .namedStandard)
            #expect(draft.metadata.topics == ["standards", "w3c", "TODO-domain-tag"])
        }

        @Test func `a hyphenated spec number is still a number`() throws {
            let draft = try RepositoryPolicyMetadataTests.draft("swift-iso/swift-iso-14496-22")
            #expect(draft.kind == .singleSpec)
        }

        @Test func `a target that is not owner slash name is refused`() {
            #expect(throws: Repository.Policy.Metadata.Error.malformedRepository("swift-ietf")) {
                try Repository.Policy.Metadata.Draft(target: "swift-ietf")
            }
        }
    }
}
