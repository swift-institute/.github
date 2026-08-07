import CI_Contract
import CI_Workflow
import Foundation
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
    static func subject(_ name: String, _ contents: [String: String]) throws -> (
        CI.Validation.Subject, URL
    ) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("c1b-\(name)-\(UUID().uuidString)")
        for (relative, text) in contents {
            let file = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        return (
            CI.Validation.Subject(
                repository: "swift-institute-test/\(name)", root: root.path), root
        )
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

        @Test func `each validator names the script it retires`() {
            let scripts = CI.Validation.Registry.validators.compactMap(\.retiredScript)
            #expect(scripts.contains(".github/scripts/validate-ci-matrix.py"))
            #expect(
                scripts.contains(".github/scripts/validate-composite-action-descriptions.py"))
            #expect(scripts.contains(".github/scripts/validate-embedded-job.py"))
            #expect(scripts.contains(".github/scripts/validate-env-context.py"))
        }
    }

    @Suite
    struct `Environment Context` {
        typealias Rule = CI.Validation.EnvironmentContext

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
            let (subject, root) = try CIValidationC1bTests.subject(
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
            defer { try? FileManager.default.removeItem(at: root) }
            let findings = try Rule().findings(in: subject)
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
                let (subject, root) = try CIValidationC1bTests.subject(
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
                defer { try? FileManager.default.removeItem(at: root) }
                let findings = try CI.Validation.EmbeddedJob().findings(in: subject)
                #expect(findings.isEmpty == satisfied, "continue-on-error: \(value)")
            }
        }

        @Test func `a repository without swift-ci_yml is out of scope not clean`() throws {
            // Silence here means "not asked". The distinction is why the
            // corpus keeps `no-swift-ci-yml` as an edge scenario rather
            // than folding it into pass.
            let (subject, root) = try CIValidationC1bTests.subject(
                "no-swift-ci", [".github/workflows/lint.yml": "name: Lint\non:\n  push:\n"])
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(try CI.Validation.EmbeddedJob().findings(in: subject).isEmpty)
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
            let (wrapper, wrapperRoot) = try CIValidationC1bTests.subject(
                "wrapper", workflow)
            defer { try? FileManager.default.removeItem(at: wrapperRoot) }
            let scoped = CI.Validation.Subject(
                repository: "swift-primitives/.github", root: wrapper.root)
            #expect(try CI.Validation.CIMatrix().findings(in: scoped).isEmpty)
            #expect(!(try CI.Validation.CIMatrix().findings(in: wrapper).isEmpty))
        }

        @Test func `the two postures are reported under different rules`() throws {
            // The whole point of the pair: nightly must be advisory,
            // Windows must not be. A validator that reported both under
            // one identifier would let a Windows regression be triaged as
            // toolchain noise.
            let (subject, root) = try CIValidationC1bTests.subject(
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
            defer { try? FileManager.default.removeItem(at: root) }
            let findings = try CI.Validation.CIMatrix().findings(in: subject)
            #expect(findings.map(\.rule) == ["CI-010", "CI-099"])
        }

        @Test func `a collapsed apple matrix names every missing platform in order`() throws {
            let (subject, root) = try CIValidationC1bTests.subject(
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
            defer { try? FileManager.default.removeItem(at: root) }
            let findings = try CI.Validation.CIMatrix().findings(in: subject)
            #expect(findings.count == 1)
            #expect(
                findings[0].message.hasSuffix("missing: ['tvOS', 'visionOS', 'watchOS']"))
        }

        @Test func `a wrong runner quotes the value it read back`() throws {
            let (subject, root) = try CIValidationC1bTests.subject(
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
            defer { try? FileManager.default.removeItem(at: root) }
            let findings = try CI.Validation.CIMatrix().findings(in: subject)
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
            let (subject, root) = try CIValidationC1bTests.subject(
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
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(try CI.Validation.CompositeActionDescriptions().findings(in: subject).isEmpty)
        }

        @Test func `all three description positions are scanned in order`() throws {
            let (subject, root) = try CIValidationC1bTests.subject(
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
            defer { try? FileManager.default.removeItem(at: root) }
            let findings = try CI.Validation.CompositeActionDescriptions().findings(in: subject)
            #expect(findings.count == 3)
            #expect(findings[0].message.contains("top-level description"))
            #expect(findings[1].message.contains("inputs.token description"))
            #expect(findings[2].message.contains("outputs.key description"))
        }

        @Test func `a repository with no actions directory is silent`() throws {
            let (subject, root) = try CIValidationC1bTests.subject(
                "no-actions", ["README.md": "# nothing here\n"])
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(try CI.Validation.CompositeActionDescriptions().findings(in: subject).isEmpty)
        }
    }
}
