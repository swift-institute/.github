import CI_Contract
import CI_Workflow
import Testing

@testable import CI_Validation

/// The four workflow-shape rules ported as class C1b: `CI-010`/`CI-099`,
/// `CI-021`, `CI-102`, `CI-103`.
///
/// The fixture corpora themselves are exercised by
/// `CIValidationHarnessTests`, which runs every registered validator over
/// every scenario. What is tested here is what a corpus cannot show: the
/// predicates that decide *between* two nearly identical shapes, where a
/// wrong reading passes every fixture because no fixture distinguishes
/// them.
@Suite
struct CIValidationC1bTests {
    /// A throwaway repository carrying one or more files.
    ///
    /// Composed over the suite-shared `TemporaryRepository` rather than
    /// re-declaring temporary-directory handling per class: its `deinit`
    /// owns the cleanup, which is also what keeps these controls free of
    /// a `try?` in every `defer`.
    static func repository(_ name: String, _ contents: [String: String]) -> TemporaryRepository {
        let repository = TemporaryRepository(repository: "swift-institute-test/\(name)")
        for (relative, text) in contents { repository.write(text, to: relative) }
        return repository
    }

    @Suite
    struct Registration {
        @Test func `every C1b rule resolves to its validator`() {
            #expect(CI.Validation.Registry.validator(for: "CI-010") is CI.Validation.CIMatrix)
            #expect(CI.Validation.Registry.validator(for: "CI-099") is CI.Validation.CIMatrix)
            #expect(
                CI.Validation.Registry.validator(for: "CI-102")
                    is CI.Validation.CompositeActionDescriptions)
            #expect(CI.Validation.Registry.validator(for: "CI-021") is CI.Validation.EmbeddedJob)
            #expect(
                CI.Validation.Registry.validator(for: "CI-103")
                    is CI.Validation.EnvironmentContext)
        }

        /// `validate-base.yml` dispatches by the retired script's path,
        /// not by rule, so a caller needs no edit when its rule crosses
        /// to Swift — and the path keeps resolving after the file is
        /// deleted. Each of the four must answer to the exact string its
        /// caller still declares.
        @Test(arguments: [
            (".github/scripts/validate-ci-matrix.py", "CI-010"),
            (".github/scripts/validate-composite-action-descriptions.py", "CI-102"),
            (".github/scripts/validate-embedded-job.py", "CI-021"),
            (".github/scripts/validate-env-context.py", "CI-103"),
        ])
        func `each retired script resolves to its replacement`(
            script: String, rule: CI.Validation.Rule
        ) {
            let validator = CI.Validation.Registry.validator(replacing: script)
            #expect(validator?.rules.contains(rule) == true)
        }
    }

    @Suite
    struct `Environment Context` {
        typealias Rule = CI.Validation.EnvironmentContext

        /// The live workflow must keep the temporary main-nightly exception
        /// as one immutable image identity at both the plan and container
        /// boundaries. This is a real-tree negative control: changing the
        /// container back to `${{ env.SWIFT_MAIN_NIGHTLY_IMAGE }}` makes this
        /// assertion fail even if a future validator change misses the use.
        @Test func `the shipped main nightly container is a fixed matching digest`() throws {
            let text = try #require(
                try RepositoryUnderTest.subject.text(at: ".github/workflows/swift-ci.yml"))
            let document = try CI.Workflow.Document(name: "swift-ci.yml", text: text)
            let job = try #require(document.jobs.first { $0.name == "linux-nightly" })
            let container = try #require(job.body["container"]?.text)
            let planImage = try #require(document.body?["env"]?["SWIFT_MAIN_NIGHTLY_IMAGE"]?.text)

            #expect(
                container
                    == "swiftlang/swift@sha256:f577f95edfb85cf3bdc45eb0badaab09239de5c86c69b3b6d594cc62916c0a7d")
            #expect(container == planImage)
        }

        @Test(arguments: [
            "swift:${{ env.SWIFT_VERSION }}",
            "swift:${{env.SWIFT_VERSION}}",
            "swift:${{   env.X }}",
            "prefix ${{ env.A }} suffix",
        ])
        func `an env read is found through any spacing`(text: String) {
            #expect(Rule.referencesEnvironment(.text(text)))
        }

        @Test(arguments: [
            "${{ inputs.swift-version }}",
            "${{ vars.RUNNER }}",
            "${{ matrix.platform }}",
            "${{ github.ref }}",
            "${{ secrets.TOKEN }}",
            "ubuntu-latest",
            "${{ env. }}",
            "${{ environment.X }}",
        ])
        func `no other context is flagged`(text: String) {
            // The recommended fix for a CI-103 violation is `inputs.` or
            // `vars.`; a validator that flagged those would be flagging
            // its own remedy. `${{ env. }}` with no name is not a read,
            // and `environment.` is a different word that happens to
            // share a prefix.
            #expect(!Rule.referencesEnvironment(.text(text)))
        }

        @Test func `a list-form runs-on is searched element by element`() {
            #expect(
                Rule.referencesEnvironment(
                    .sequence([.text("self-hosted"), .text("${{ env.LABEL }}")])))
        }

        @Test func `a non-text scalar cannot carry an expression`() {
            // Stringifying a boolean to search it is the conflation the
            // contract exists to prevent.
            #expect(!Rule.referencesEnvironment(.boolean(true)))
            #expect(!Rule.referencesEnvironment(.integer(103)))
            #expect(!Rule.referencesEnvironment(.null))
        }

        @Test func `one job can violate on both fields and is reported twice`() throws {
            let fixture = CIValidationC1bTests.repository(
                "both-fields",
                [
                    ".github/workflows/ci.yml": """
                        name: CI
                        on:
                          push:
                        jobs:
                          build:
                            runs-on: ${{ env.RUNNER }}
                            container:
                              image: swift:${{ env.SWIFT_VERSION }}
                            steps:
                              - run: swift build
                        """
                ])
            let findings = try Rule().findings(in: fixture.subject)
            #expect(findings.count == 2)
            #expect(findings[0].message.contains("`runs-on:`"))
            #expect(findings[1].message.contains("`container.image:`"))
        }
    }

    @Suite
    struct `Embedded Job` {
        @Test func `only the boolean true satisfies the advisory posture`() throws {
            // Narrower than CI-105 on purpose: CI-105 asks whether
            // Actions will reject the shape, so a quoted "true" is enough
            // to worry about; CI-021 asks whether the posture is
            // declared, and a string is not a declaration.
            for (value, satisfied) in [("true", true), ("'true'", false), ("false", false)] {
                let fixture = CIValidationC1bTests.repository(
                    "embedded",
                    [
                        ".github/workflows/swift-ci.yml": """
                            name: Swift CI
                            on:
                              workflow_call:
                            jobs:
                              embedded:
                                runs-on: ubuntu-latest
                                continue-on-error: \(value)
                                steps:
                                  - run: swift build
                            """
                    ])
                let findings = try CI.Validation.EmbeddedJob().findings(in: fixture.subject)
                #expect(findings.isEmpty == satisfied, "continue-on-error: \(value)")
            }
        }

        @Test func `a repository without swift-ci_yml is out of scope not clean`() throws {
            // Silence here means "not asked". The distinction is why the
            // corpus keeps `no-swift-ci-yml` as an edge scenario rather
            // than folding it into pass.
            let fixture = CIValidationC1bTests.repository(
                "no-swift-ci", [".github/workflows/lint.yml": "name: Lint\non:\n  push:\n"])
            #expect(try CI.Validation.EmbeddedJob().findings(in: fixture.subject).isEmpty)
        }
    }

    @Suite
    struct `CI Matrix` {
        @Test func `a layer wrapper is out of scope`() throws {
            // Layer wrappers host their own swift-ci.yml with
            // intentionally different shapes. The script-level gate is
            // what stops a misconfigured dispatch from reporting the
            // whole ecosystem as defective.
            let workflow = [".github/workflows/swift-ci.yml": "name: Swift CI\njobs: {}\n"]
            let fixture = CIValidationC1bTests.repository("wrapper", workflow)
            let scoped = CI.Validation.Subject(
                repository: "swift-primitives/.github", root: fixture.root)
            #expect(try CI.Validation.CIMatrix().findings(in: scoped).isEmpty)
            #expect(!(try CI.Validation.CIMatrix().findings(in: fixture.subject).isEmpty))
        }

        @Test func `the two postures are reported under different rules`() throws {
            // The whole point of the pair: nightly must be advisory,
            // Windows must not be. A validator that reported both under
            // one identifier would let a Windows regression be triaged as
            // toolchain noise.
            let fixture = CIValidationC1bTests.repository(
                "postures",
                [
                    ".github/workflows/swift-ci.yml": """
                        name: Swift CI
                        on:
                          workflow_call:
                        jobs:
                          macos-release:
                            runs-on: macos-26
                            steps:
                              - run: swift build
                          linux-release:
                            runs-on: ubuntu-latest
                            steps:
                              - run: swift build
                          linux-nightly:
                            runs-on: ubuntu-latest
                            steps:
                              - run: swift build
                          windows-release:
                            runs-on: windows-latest
                            continue-on-error: true
                            steps:
                              - run: swift build
                          apple-simulator-build:
                            runs-on: macos-26
                            continue-on-error: true
                            strategy:
                              matrix:
                                platform: [iOS, tvOS, watchOS, visionOS]
                            steps:
                              - run: xcodebuild
                        """
                ])
            let findings = try CI.Validation.CIMatrix().findings(in: fixture.subject)
            #expect(findings.map(\.rule) == ["CI-010", "CI-099"])
        }

        @Test func `a collapsed apple matrix names every missing platform in order`() throws {
            let fixture = CIValidationC1bTests.repository(
                "collapsed",
                [
                    ".github/workflows/swift-ci.yml": """
                        name: Swift CI
                        on:
                          workflow_call:
                        jobs:
                          macos-release:
                            runs-on: macos-26
                          linux-release:
                            runs-on: ubuntu-latest
                          linux-nightly:
                            runs-on: ubuntu-latest
                            continue-on-error: true
                          windows-release:
                            runs-on: windows-latest
                          apple-simulator-build:
                            runs-on: macos-26
                            continue-on-error: true
                            strategy:
                              matrix:
                                platform: [iOS]
                        """
                ])
            let findings = try CI.Validation.CIMatrix().findings(in: fixture.subject)
            #expect(findings.count == 1)
            #expect(
                findings[0].message.hasSuffix("missing: ['tvOS', 'visionOS', 'watchOS']"))
        }

        @Test func `a wrong runner quotes the value it read back`() throws {
            let fixture = CIValidationC1bTests.repository(
                "wrong-runner",
                [
                    ".github/workflows/swift-ci.yml": """
                        name: Swift CI
                        on:
                          workflow_call:
                        jobs:
                          macos-release:
                            runs-on: ubuntu-latest
                          linux-release:
                            runs-on: ubuntu-latest
                          linux-nightly:
                            runs-on: ubuntu-latest
                            continue-on-error: true
                          windows-release:
                            runs-on: windows-latest
                          apple-simulator-build:
                            runs-on: macos-26
                            continue-on-error: true
                            strategy:
                              matrix:
                                platform: [iOS, tvOS, watchOS, visionOS]
                        """
                ])
            let findings = try CI.Validation.CIMatrix().findings(in: fixture.subject)
            #expect(findings.count == 1)
            #expect(
                findings[0].message
                    == "macos-release: runs-on must reference a macos runner per [CI-010]; "
                    + "got 'ubuntu-latest'")
        }
    }

    @Suite
    struct `Composite Action Descriptions` {
        @Test func `an expression outside a description is left alone`() throws {
            // The edge corpora hold this line: an output's `value:` and a
            // step's `env:` are exactly where expressions belong.
            let fixture = CIValidationC1bTests.repository(
                "legit",
                [
                    ".github/actions/legit/action.yml": """
                        name: Legit
                        description: Does a thing.
                        outputs:
                          key:
                            description: The cache key.
                            value: ${{ steps.compute.outputs.key }}
                        runs:
                          using: composite
                          steps:
                            - shell: bash
                              env:
                                REF: ${{ github.ref }}
                              run: echo "$REF"
                        """
                ])
            #expect(try CI.Validation.CompositeActionDescriptions().findings(in: fixture.subject).isEmpty)
        }

        @Test func `all three description positions are scanned in order`() throws {
            let fixture = CIValidationC1bTests.repository(
                "broken",
                [
                    ".github/actions/broken/action.yml": """
                        name: Broken
                        description: Uses ${{ inputs.name }} badly.
                        inputs:
                          token:
                            description: The ${{ github.token }} to use.
                        outputs:
                          key:
                            description: Keyed on ${{ github.sha }}.
                        runs:
                          using: composite
                          steps: []
                        """
                ])
            let findings = try CI.Validation.CompositeActionDescriptions().findings(in: fixture.subject)
            #expect(findings.count == 3)
            #expect(findings[0].message.contains("top-level description"))
            #expect(findings[1].message.contains("inputs.token description"))
            #expect(findings[2].message.contains("outputs.key description"))
        }

        @Test func `a repository with no actions directory is silent`() throws {
            let fixture = CIValidationC1bTests.repository(
                "no-actions", ["README.md": "# nothing here\n"])
            #expect(try CI.Validation.CompositeActionDescriptions().findings(in: fixture.subject).isEmpty)
        }
    }
}
