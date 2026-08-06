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
        // K-12 property transfer: the layer's lint bundle rides the leaf.
        #expect(text.contains("    with:\n      lint-bundle: primitives"))
        // R-08 context preservation: the dead wrapper hop's display
        // segment rides the job name, keeping `ci / matrix / <job>`.
        #expect(text.contains("  ci:\n    name: ci / matrix\n    uses:"))
        let withSecrets = Repository.Policy.Caller.Render.direct(
            caller, privateDependencyClosure: true)
        #expect(withSecrets.contains(
            "      SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY }}"))
        #expect(!withSecrets.contains("PRIVATE_REPO_TOKEN"))
        #expect(!withSecrets.contains("secrets: inherit"))
    }

    @Test
    func directFormTransfersEachLayersLintBundle() throws {
        for (layer, bundle) in [
            (Repository.Policy.Caller.Layer.primitives, "primitives"),
            (.standards, "standards"),
            (.institute, "institute"),
        ] {
            let caller = try Repository.Policy.Caller(
                repository: "\(layer.wrapperOrganization)/swift-demo", layer: layer)
            let text = Repository.Policy.Caller.Render.direct(caller)
            #expect(text.contains("      lint-bundle: \(bundle)"))
        }
        // Caller inputs follow the layer-owned line in canonical order.
        let withInputs = try Repository.Policy.Caller(
            repository: "swift-standards/swift-demo", layer: .standards,
            inputs: [(key: "platform-support", value: "macos-linux")])
        let text = Repository.Policy.Caller.Render.direct(withInputs)
        #expect(text.contains(
            "    with:\n      lint-bundle: standards\n      platform-support: macos-linux"))
    }

    @Test
    func rulePackRepositoriesCarryTheNotifyJob() throws {
        for repository in Repository.Policy.Caller.linterRulePackRepositories {
            let layer: Repository.Policy.Caller.Layer =
                repository.hasPrefix("swift-primitives/") ? .primitives
                : repository.hasPrefix("swift-standards/") ? .standards : .institute
            let caller = try Repository.Policy.Caller(repository: repository, layer: layer)
            let text = Repository.Policy.Caller.Render.direct(caller)
            #expect(text.contains("  notify-linter-republish:"))
            #expect(text.contains("if: github.event_name == 'push' && github.ref == 'refs/heads/main'"))
            #expect(text.contains("uses: swift-institute/.github/.github/workflows/notify-linter-republish.yml@main"))
            #expect(text.contains("      SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY }}"))
            #expect(!text.contains("SWIFT_INSTITUTE_BOT_APP_CLIENT_ID"))
        }
    }

    @Test
    func ordinaryRepositoriesDoNotCarryTheNotifyJob() throws {
        let caller = try Repository.Policy.Caller(
            repository: "swift-primitives/swift-bool-primitives", layer: .primitives)
        #expect(!Repository.Policy.Caller.Render.direct(caller).contains("notify-linter-republish"))
        // Near miss: a similarly named repo NOT in the exact-coordinate set.
        let nearMiss = try Repository.Policy.Caller(
            repository: "swift-primitives/swift-linter-rules-tools", layer: .primitives)
        #expect(!Repository.Policy.Caller.Render.direct(nearMiss).contains("notify-linter-republish"))
    }

    /// F14 cutover: the App id is a variable, never a forwarded secret.
    /// The near-miss half matters more than the positive half — a
    /// renderer that regressed to the historical two-secret spelling
    /// would still emit valid YAML and still pass every other test here.
    @Test
    func terminalProfileForwardsOnlyThePrivateKeyAndNeverTheId() throws {
        #expect(Repository.Policy.Caller.terminalSecretNames == [
            "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
        ])
        #expect(Repository.Policy.Caller.terminalVariableNames == [
            "SWIFT_INSTITUTE_BOT_APP_ID",
        ])
        // The two sets are disjoint: no name may be both.
        for name in Repository.Policy.Caller.terminalVariableNames {
            #expect(!Repository.Policy.Caller.terminalSecretNames.contains(name))
        }

        // No rendered form may name an id-shaped secret. Checked over
        // every layer and over both the ordinary and the rule-pack leaf,
        // with and without the private dependency closure.
        var rendered: [String] = []
        for layer in Repository.Policy.Caller.Layer.allCases {
            let ordinary = try Repository.Policy.Caller(
                repository: "\(layer.wrapperOrganization)/swift-demo", layer: layer)
            rendered.append(Repository.Policy.Caller.Render.direct(ordinary))
            rendered.append(Repository.Policy.Caller.Render.direct(
                ordinary, privateDependencyClosure: true))
        }
        for repository in Repository.Policy.Caller.linterRulePackRepositories {
            let layer: Repository.Policy.Caller.Layer =
                repository.hasPrefix("swift-primitives/") ? .primitives
                : repository.hasPrefix("swift-standards/") ? .standards : .institute
            rendered.append(Repository.Policy.Caller.Render.direct(
                try Repository.Policy.Caller(repository: repository, layer: layer)))
        }

        // Positive control: the corpus is non-empty and does contain the
        // one name that IS expected, so a zero below is a measurement.
        #expect(!rendered.isEmpty)
        #expect(rendered.contains {
            $0.contains("SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY")
        })

        for text in rendered {
            #expect(!text.contains("secrets.SWIFT_INSTITUTE_BOT_APP_ID"))
            #expect(!text.contains("SWIFT_INSTITUTE_BOT_APP_CLIENT_ID"))
            #expect(!text.contains("PRIVATE_REPO_TOKEN"))
            #expect(!text.contains("secrets: inherit"))
            // The id is not delivered by the leaf at all — not as a
            // secret and not as a caller-side `vars` forward. It is
            // resolved inside the callee from the org variable.
            #expect(!text.contains("SWIFT_INSTITUTE_BOT_APP_ID"))
        }
    }

    @Test
    func malformedRepositoryRefuses() {
        #expect(throws: Repository.Policy.Caller.Error.self) {
            try Repository.Policy.Caller(repository: "no-slash", layer: .primitives)
        }
    }
}
