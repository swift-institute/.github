import CI_Contract
import CI_Validation
import Foundation
import Testing

@Suite
struct CIValidationSubOrgWrappersTests {
    static func findings(
        _ repository: String, files: [String: String]
    ) throws -> [CI.Validation.Finding] {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "c3-suborg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, text) in files {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try CI.Validation.SubOrgWrappers().findings(
            in: CI.Validation.Subject(repository: repository, root: root.path))
    }

    static let wrapper = [".github/workflows/swift-ci.yml": "name: swift-ci\non:\n  workflow_call:\n"]

    /// The rule is a negative existence check on exactly one coordinate:
    /// a wrapper, in a sub-org's `.github` repository. Each of the three
    /// conditions alone is silent.
    @Test
    func firesOnlyOnAWrapperInASubOrganizationDotGithubRepository() throws {
        #expect(try Self.findings("swift-ietf/.github", files: Self.wrapper).count == 1)
        // A sub-org `.github` without the wrapper — the canonical state.
        #expect(try Self.findings(
            "swift-ietf/.github",
            files: [".github/workflows/other.yml": "name: other\n"]).isEmpty)
        // The wrapper, but not in a `.github` repository.
        #expect(try Self.findings("swift-ietf/swift-rfc-3986", files: Self.wrapper).isEmpty)
        // The wrapper in a `.github` repository, but not a sub-org's —
        // the layer wrappers are exactly where it belongs.
        #expect(try Self.findings("swift-standards/.github", files: Self.wrapper).isEmpty)
    }

    /// The message routes the reader to the *parent layer* wrapper, and
    /// which parent depends on whether the authority is an L2 or an L3
    /// sub-org. Naming the wrong one would send a repair to a workflow
    /// that does not serve it.
    @Test
    func theRepairNamesTheAuthoritysOwnParentLayerWrapper() throws {
        let standards = try Self.findings("swift-iso/.github", files: Self.wrapper)
        #expect(standards[0].message.contains(
            "swift-standards/.github/.github/workflows/swift-ci.yml@main"))

        let foundations = try Self.findings("swift-microsoft/.github", files: Self.wrapper)
        #expect(foundations[0].message.contains(
            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"))
    }

    /// The corpus reports every scenario as `swift-institute-test/<name>`,
    /// an owner no production sweep passes, so without the marker the
    /// sub-org branch would be unreachable from the fixture tree. The
    /// marker names a sub-org or it names nothing — it cannot invent one.
    @Test
    func theFixtureMarkerReachesTheSubOrganizationBranchAndOnlyForRealOnes() throws {
        var files = Self.wrapper
        files[".github-as-sub-org"] = "swift-ietf\n"
        #expect(try Self.findings("swift-institute-test/scenario", files: files).count == 1)

        files[".github-as-sub-org"] = "not-a-sub-org\n"
        #expect(try Self.findings("swift-institute-test/scenario", files: files).isEmpty)
    }

    /// The thirteen authorities, partitioned by the layer wrapper they
    /// route through. `ThinCallers` reads this same set for `[CI-059]`'s
    /// inversion rather than restating it — two spellings of thirteen
    /// organizations is the drift the validators manifest exists because
    /// of.
    @Test
    func theSubOrganizationSetIsThirteenAndPartitioned() {
        #expect(CI.Validation.SubOrgWrappers.standardsSubOrganizations.count == 11)
        #expect(CI.Validation.SubOrgWrappers.foundationsSubOrganizations.count == 2)
        #expect(CI.Validation.SubOrgWrappers.subOrganizations.count == 13)
        #expect(CI.Validation.SubOrgWrappers.standardsSubOrganizations
            .isDisjoint(with: CI.Validation.SubOrgWrappers.foundationsSubOrganizations))
    }

    @Test
    func theRuleResolvesToThisValidator() {
        #expect(CI.Validation.Registry.validator(for: "CI-004b") is CI.Validation.SubOrgWrappers)
    }
}
