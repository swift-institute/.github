import Foundation
import Repository_Policy
import Testing

@Suite
struct RepositoryPolicyCallerTests {
    @Test
    func currentFormMatchesIncumbentShape() throws {
        let caller = try Repository.Policy.Caller(
            repository: "swift-primitives/swift-bool-primitives",
            layer: .primitives)
        let text = Repository.Policy.Caller.Render.current(caller)
        #expect(text.contains("uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main"))
        #expect(text.contains("secrets: inherit"))
        #expect(text.contains("tags:\n      - '*'"))
        #expect(text.hasSuffix("\n"))
        #expect(!text.contains("with:"))
    }

    @Test
    func crossOrgCurrentFormForwardsLegacyFourSecrets() throws {
        let caller = try Repository.Policy.Caller(
            repository: "swift-ietf/swift-rfc-2045", layer: .standards,
            inputs: [(key: "platform-support", value: "macos-linux")])
        let text = Repository.Policy.Caller.Render.current(caller)
        #expect(text.contains("uses: swift-standards/.github/.github/workflows/swift-ci.yml@main"))
        #expect(!text.contains("secrets: inherit"))
        for name in Repository.Policy.Caller.legacySecretNames {
            #expect(text.contains("      \(name): ${{ secrets.\(name) }}"))
        }
        #expect(text.contains("    with:\n      platform-support: macos-linux"))
    }

    @Test
    func inputsEmitInCanonicalOrderRegardlessOfSpecOrder() throws {
        let caller = try Repository.Policy.Caller(
            repository: "swift-foundations/swift-demo", layer: .institute,
            inputs: [
                (key: "docs-umbrella-module", value: "Demo"),
                (key: "swift-version", value: "6.2"),
            ])
        let text = Repository.Policy.Caller.Render.current(caller)
        let swiftVersion = try #require(text.range(of: "swift-version: 6.2"))
        let docs = try #require(text.range(of: "docs-umbrella-module: Demo"))
        #expect(swiftVersion.lowerBound < docs.lowerBound)
    }

    @Test
    func directFormHasNoTagTriggerAndCallsUniversal() throws {
        let caller = try Repository.Policy.Caller(
            repository: "swift-primitives/swift-bool-primitives",
            layer: .primitives)
        let text = Repository.Policy.Caller.Render.direct(caller)
        #expect(!text.contains("tags:"))
        #expect(text.contains("uses: swift-institute/.github/.github/workflows/swift-ci.yml@main"))
        #expect(!text.contains("secrets"))
        let withSecrets = Repository.Policy.Caller.Render.direct(
            caller, privateDependencyClosure: true)
        #expect(withSecrets.contains(
            "      SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY }}"))
        #expect(!withSecrets.contains("PRIVATE_REPO_TOKEN"))
        #expect(!withSecrets.contains("secrets: inherit"))
    }

    @Test
    func malformedRepositoryRefuses() {
        #expect(throws: Repository.Policy.Caller.Error.self) {
            try Repository.Policy.Caller(repository: "no-slash", layer: .primitives)
        }
    }
}
