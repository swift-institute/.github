import Foundation
import Repository_Policy
import Testing

@Suite
struct RepositoryPolicyTests {
    @Test
    func eligibilityFixtures() throws {
        let url = try #require(Bundle.module.url(forResource: "eligibility", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))

        #expect(fixtures.count == 9)
        for fixture in fixtures {
            let state = fixture.pvr.flatMap(RepositoryPolicy.VulnerabilityReporting.init(rawValue:))
            let decision = RepositoryPolicy.decision(
                for: fixture.repository,
                manifestKind: fixture.manifestKind,
                vulnerabilityReporting: state
            )
            #expect(render(decision) == fixture.decision, "\(fixture.name)")
        }
    }

    @Test
    func scopeRejectsDeniedOwner() {
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(
                organization: nil,
                repository: "tenthijeboonkkamp/package"
            )
        }
    }

    @Test
    func scopeRequiresExactlyOneSelector() {
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(organization: nil, repository: nil)
        }
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(
                organization: "swift-foundations",
                repository: "swift-foundations/swift-example"
            )
        }
    }

    @Test
    func surfacePolicyAcceptsWhitelistedThinCaller() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on:
                  push:
                  pull_request:
                  workflow_dispatch:
                jobs:
                  ci:
                    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["pull_request", "push", "workflow_dispatch"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(report.passed)
        #expect(report.actionFiles == 1)
        #expect(report.issueFormFiles == 0)
    }

    @Test
    func surfacePolicyRejectsUnlistedTriggerUseAndInlineJob() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on:
                  schedule:
                    - cron: "0 4 * * *"
                jobs:
                  ci:
                    runs-on: ubuntu-latest
                    steps:
                      - uses: actions/checkout@v7
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["push"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(
            Set(report.violations.map(\.identifier))
                == ["REPO-ACTIONS-003", "REPO-ACTIONS-004", "REPO-ACTIONS-005"]
        )
    }

    @Test
    func surfacePolicyAcceptsExplicitToolOwnedWorkflowAndAction() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/lint.yml": """
                name: Lint
                on:
                  workflow_call:
                jobs:
                  lint:
                    runs-on: ubuntu-latest
                    steps:
                      - uses: ./.github/actions/install
                """,
                ".github/actions/install/action.yml": """
                name: Install
                description: Install the tool
                runs:
                  using: composite
                  steps:
                    - uses: actions/checkout@v7
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-linter",
            repositoryClass: .tool,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .tool,
                        repository: "swift-foundations/swift-linter",
                        path: ".github/workflows/lint.yml",
                        kind: .toolWorkflow,
                        triggers: ["workflow_call"],
                        uses: ["./.github/actions/install"]
                    ),
                    .init(
                        repositoryClass: .tool,
                        repository: "swift-foundations/swift-linter",
                        path: ".github/actions/install/action.yml",
                        kind: .toolAction,
                        triggers: [],
                        uses: ["actions/checkout@v7"]
                    ),
                ],
                exemptions: []
            )
        )

        #expect(report.passed)
        #expect(report.actionFiles == 2)
    }

    @Test
    func surfacePolicyDeniesLocalIssueFormsAndHonorsExactTypedExemptions() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/recovery.yml": """
                name: Recovery
                on: workflow_dispatch
                jobs:
                  recover:
                    runs-on: ubuntu-latest
                    steps:
                      - uses: actions/checkout@v7
                """,
                ".github/ISSUE_TEMPLATE/bug.yml": "name: Bug\n",
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let denied = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )
        #expect(
            Set(denied.violations.map(\.identifier))
                == ["REPO-ACTIONS-001", "REPO-FORMS-001"]
        )

        let exempted = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [],
                exemptions: [
                    .init(
                        surface: .actions,
                        repository: "swift-foundations/swift-example",
                        path: ".github/workflows/recovery.yml",
                        reason: "bounded recovery until the central operation lands"
                    ),
                    .init(
                        surface: .issueForms,
                        repository: "swift-foundations/swift-example",
                        path: ".github/ISSUE_TEMPLATE/bug.yml",
                        reason: "repository requires a typed form unavailable at organization scope"
                    ),
                ]
            )
        )
        #expect(exempted.passed)
        #expect(exempted.exemptionsApplied == 2)
    }

    @Test
    func remoteSurfaceSnapshotUsesTheSameTypedPolicy() throws {
        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on: [push, pull_request]
                jobs:
                  ci:
                    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
                """,
                ".github/ISSUE_TEMPLATE/bug.yml": "name: Bug\n",
                "Sources/Example.swift": "public struct Example {}\n",
            ],
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["pull_request", "push"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(report.actionFiles == 1)
        #expect(report.issueFormFiles == 1)
        #expect(report.violations.map(\.identifier) == ["REPO-FORMS-001"])
    }

    @Test
    func instituteDefaultSurfacePolicyMatchesTheDesignedFleet() throws {
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: RepositoryPolicy.SurfacePolicy.instituteDefaultURL
        )

        #expect(policy.schemaVersion == 1)

        // The generic package thin-caller grant admits exactly the designed
        // `uses:` targets: the three layer swift-ci and swift-docs wrappers,
        // plus the notify-linter-republish reusable the rule-pack repositories
        // call on push to main.
        let generic = try #require(
            policy.actionGrants.first {
                $0.repository == nil && $0.path == ".github/workflows/ci.yml"
            }
        )
        #expect(generic.repositoryClass == .package)
        #expect(generic.kind == .thinCaller)
        #expect(generic.triggers == ["pull_request", "push", "workflow_dispatch"])
        #expect(
            generic.uses == [
                "swift-foundations/.github/.github/workflows/swift-ci.yml@main",
                "swift-foundations/.github/.github/workflows/swift-docs.yml@main",
                "swift-institute/.github/.github/workflows/notify-linter-republish.yml@main",
                "swift-primitives/.github/.github/workflows/swift-ci.yml@main",
                "swift-primitives/.github/.github/workflows/swift-docs.yml@main",
                "swift-standards/.github/.github/workflows/swift-ci.yml@main",
                "swift-standards/.github/.github/workflows/swift-docs.yml@main",
            ]
        )

        // swift-linter is the tool-host: repository-scoped grants for its own
        // thin caller and its workflow_call reusable, nothing broader.
        let linterGrants = policy.actionGrants.filter {
            $0.repository == "swift-foundations/swift-linter"
        }
        #expect(linterGrants.count == 2)
        #expect(linterGrants.allSatisfy { $0.repositoryClass == .tool })
        #expect(
            linterGrants.first { $0.path == ".github/workflows/lint.yml" }?.kind
                == .toolWorkflow
        )

        #expect(policy.actionGrants.count == 3)

        // Typed exemptions carry exact repository and path scope.
        #expect(
            policy.exemptions.map { "\($0.repository):\($0.path)" }.sorted() == [
                "swift-foundations/swift-linter:.github/workflows/publish-ci-binaries.yml",
                "swift-foundations/swift-pdf:.github/workflows/windows-6.4-proof.yml",
                "swift-foundations/swift-pdf:.github/workflows/windows-existential-repro.yml",
                "swift-iso/swift-iso-32000:.github/workflows/no-verbatim-spec-text.yml",
            ]
        )
        #expect(policy.exemptions.allSatisfy { $0.surface == .actions })
    }

    // Positive control: the shipped policy must still DENY. A whitelist whose
    // gate has never been observed to fire is evidence of nothing, so these
    // fixtures are deliberately non-conformant and the check must flag them.
    @Test
    func instituteDefaultSurfacePolicyStillFiresOnNonConformantFixtures() throws {
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: RepositoryPolicy.SurfacePolicy.instituteDefaultURL
        )

        // A sha-pinned wrapper ref cannot match the granted `@main` string.
        let shaPinned = try RepositoryPolicy.validateSurface(
            repository: "swift-primitives/swift-example",
            repositoryClass: .package,
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on: [push, pull_request, workflow_dispatch]
                jobs:
                  ci:
                    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@0123456789abcdef0123456789abcdef01234567
                """
            ],
            policy: policy
        )
        #expect(shaPinned.violations.map(\.identifier) == ["REPO-ACTIONS-004"])

        // The swift-pdf Windows-ICE exemption is repository-exact: the same
        // path in any other repository stays denied.
        let windowsFile = """
            name: Windows 6.4 proof
            on: [push, workflow_dispatch]
            jobs:
              proof:
                runs-on: windows-2022
                steps:
                  - uses: actions/checkout@v7
            """
        let wrongRepository = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            files: [".github/workflows/windows-6.4-proof.yml": windowsFile],
            policy: policy
        )
        #expect(wrongRepository.violations.map(\.identifier) == ["REPO-ACTIONS-001"])
        let exemptedRepository = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-pdf",
            repositoryClass: .package,
            files: [".github/workflows/windows-6.4-proof.yml": windowsFile],
            policy: policy
        )
        #expect(exemptedRepository.passed)
        #expect(exemptedRepository.exemptionsApplied == 1)

        // The admitted rule-pack shape passes: layer wrapper plus the
        // notify-linter-republish target in one thin caller.
        let rulePack = try RepositoryPolicy.validateSurface(
            repository: "swift-primitives/swift-linter-primitives",
            repositoryClass: .package,
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on: [push, pull_request, workflow_dispatch]
                jobs:
                  ci:
                    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
                  notify:
                    uses: swift-institute/.github/.github/workflows/notify-linter-republish.yml@main
                """
            ],
            policy: policy
        )
        #expect(rulePack.passed)
    }

    // The `reviewAfter` key was removed from the exemption schema
    // ([swift-institute/.github#110]) because it was decoded but read
    // nowhere. Load-time validation must reject any stray occurrence of it
    // (or any other unrecognized key) so the schema and the decoder stay in
    // exact correspondence going forward.
    @Test
    func surfacePolicyRejectsUnknownExemptionKeys() throws {
        let json = """
            {
              "schemaVersion": 1,
              "actionGrants": [],
              "exemptions": [
                {
                  "surface": "actions",
                  "repository": "swift-primitives/swift-example",
                  "path": ".github/workflows/legacy.yml",
                  "reason": "fixture",
                  "reviewAfter": "2026-01-01"
                }
              ]
            }
            """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "repository-surfaces-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.SurfacePolicy.load(from: url)
        }
    }

    // MARK: - REPO-DOCS-001 (SPI publish gate over placeholder DocC catalogues)

    // Positive: `.spi.yml` at the root plus a `.docc` markdown file that still
    // carries the umbrella placeholder marker produces exactly one
    // REPO-DOCS-001 advisory, and the advisory channel does not fail `passed`.
    @Test
    func docsPlaceholderAdvisoryFiresWhenSPIYMLPublishesAMarkedCatalogue() throws {
        let root = try repositoryFixture(
            files: [
                ".spi.yml": "version: 1\n",
                "Sources/Example/Example.docc/Example.md": """
                # ``Example``

                This is the umbrella catalog placeholder. Replace this line with a one-sentence \
                summary of the module.
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.map(\.identifier) == ["REPO-DOCS-001"])
        #expect(report.advisories.first?.path == "Sources/Example/Example.docc/Example.md")
        #expect(report.passed)
    }

    // Negative: `.spi.yml` present, but the catalogue has been completed (the
    // marker is gone) — no advisory.
    @Test
    func docsPlaceholderAdvisoryIsSilentOnACompletedCatalogue() throws {
        let root = try repositoryFixture(
            files: [
                ".spi.yml": "version: 1\n",
                "Sources/Example/Example.docc/Example.md": """
                # ``Example``

                Example provides a typed configuration surface for the repository policy tool.
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // Edge/fail-closed: a marked catalogue with no `.spi.yml` at the root is
    // not publication-gated — no advisory. The gate is about publication,
    // not about placeholders in general.
    @Test
    func docsPlaceholderAdvisoryIsSilentWithoutSPIYML() throws {
        let root = try repositoryFixture(
            files: [
                "Sources/Example/Example.docc/Example.md": """
                # ``Example``

                This is the umbrella catalog placeholder. Replace this line with a one-sentence \
                summary of the module.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // MARK: - REPO-README-001 / REPO-README-002 (struck badge, struck platform matrix)

    // Positive: a development-status badge image in root README.md produces
    // exactly one REPO-README-001 advisory, and only that identifier.
    @Test
    func readmeAdvisoryFiresOnDevelopmentStatusBadge() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                ![Status](https://img.shields.io/badge/status-active--development-blue.svg)

                Example is a typed configuration surface.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.map(\.identifier) == ["REPO-README-001"])
        #expect(report.passed)
    }

    // Positive: a `## Platform Support` heading in root README.md produces
    // exactly one REPO-README-002 advisory, and only that identifier.
    @Test
    func readmeAdvisoryFiresOnPlatformSupportHeading() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                ## Platform Support

                | Platform | Minimum |
                | --- | --- |
                | macOS | 15 |
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.map(\.identifier) == ["REPO-README-002"])
        #expect(report.passed)
    }

    // Negative: a converted README carrying neither construct — no advisory
    // from either identifier.
    @Test
    func readmeAdvisoriesAreSilentOnAConvertedREADME() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                Example is a typed configuration surface for the repository policy tool.

                ## Installation

                Add the package to your manifest.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // Edge/fail-closed: both constructs present, but only inside a fenced
    // code block — the fence-stripped scan (mirroring README-017/026's
    // fence exclusion) must not see them, so no advisory from either
    // identifier.
    @Test
    func readmeAdvisoriesAreSilentInsideAFencedCodeBlock() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                ```markdown
                ![Status](https://img.shields.io/badge/status-active--development-blue.svg)

                ## Platform Support
                ```

                Example is a typed configuration surface for the repository policy tool.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // MARK: - Issue-record grammar

    @Test
    func issueRecordParserAcceptsTheCompactTaskProfile() throws {
        let record = try RepositoryPolicy.Issue.Parser.record(
            """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1
            """
        )

        #expect(record.kind == .task)
        #expect(record.owner == "swift-institute/.github")
        #expect(record.status == .active)
        #expect(record.grammarVersion == 1)
    }

    // Positive control: an omitted core field must be reported malformed,
    // not silently accepted as an otherwise clean record.
    @Test
    func issueRecordReconcilerReportsMalformedCore() {
        let report = RepositoryPolicy.Issue.reconcile([
            .init(
                coordinate: "swift-institute/.github#173",
                body: """
                    ### Kind

                    Task

                    ### Owner coordinate

                    swift-institute/.github

                    ### Status

                    Active
                    """,
                native: .init(state: .open)
            )
        ])

        #expect(report.map(\.finding) == [.malformed])
    }

    // Positive control: a core-field profile has one value. The parser must
    // not overwrite a malformed first value with a later conforming one.
    @Test
    func issueRecordReconcilerRejectsAdditionalCoreFieldContent() {
        let report = RepositoryPolicy.Issue.reconcile([
            .init(
                coordinate: "swift-institute/.github#173",
                body: """
                    ### Kind

                    not Task
                    Task

                    ### Owner coordinate

                    swift-institute/.github

                    ### Status

                    Active

                    ### Grammar version

                    1
                    """,
                native: .init(state: .open)
            )
        ])

        #expect(report.map(\.finding) == [.malformed])
    }

    @Test
    func issueRecordReconcilerSeparatesNativeStateAndUnavailableInputs() throws {
        let active = """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1
            """
        let decision = try RepositoryPolicy.Issue.Decision(
            grammarVersion: 1,
            status: "superseded",
            supersededBy: "https://github.com/swift-institute/.github/issues/174"
        )

        let report = RepositoryPolicy.Issue.reconcile([
            .init(coordinate: "z#1", body: nil, native: .init(state: .open)),
            .init(coordinate: "a#1", body: active, native: .init(state: .completed)),
            .init(coordinate: "b#1", body: active, native: .init(state: .open), decision: decision),
            .init(coordinate: "c#1", body: active, native: .init(state: .open, parent: "a#0")),
        ])

        #expect(report.map(\.coordinate) == ["a#1", "b#1", "c#1", "z#1"])
        #expect(report.map(\.finding) == [.stale, .superseded, .conforming, .unavailable])
    }

    @Test
    func issueRecordReconcilerIncludesEveryPage() {
        let report = RepositoryPolicy.Issue.reconcile(pages: [
            .init(
                inputs: [.init(coordinate: "b#2", body: nil, native: .init(state: .open))],
                hasNextPage: true
            ),
            .init(
                inputs: [.init(coordinate: "a#1", body: nil, native: .init(state: .open))],
                hasNextPage: false
            ),
        ])

        #expect(report.map(\.coordinate) == ["a#1", "b#2"])
        #expect(report.map(\.finding) == [.unavailable, .unavailable])
    }

    @Test
    func typedLifecycleRecordsRejectInvalidVersionAndDigest() {
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.CompactionCheckpoint(
                grammarVersion: 2,
                source: "https://github.com/swift-institute/.github/issues/173",
                digest: "0123456789abcdef0123456789abcdef01234567"
            )
        }
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.TerminalReceipt(
                grammarVersion: 1,
                revision: "not-a-revision",
                verification: "workspace package test"
            )
        }
    }

    @Test
    func `Issue snapshot digest matches known vectors across chunk boundaries`() {
        let vectors = [
            ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
            ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
            (String(repeating: "a", count: 64), "0098ba824b5c16427bd7a1122a5a442a25ec644d"),
            (String(repeating: "a", count: 65), "11655326c708d70319be2610e8a57d9a5b959d3b"),
        ]

        for (body, digest) in vectors {
            let snapshot = RepositoryPolicy.Issue.Snapshot(
                coordinate: "swift-institute/.github#183",
                revision: "\"known-vector\"",
                body: body,
                native: .init(state: .open)
            )

            #expect(snapshot.digest == digest)
        }
    }

    @Test
    func activeRecordCompactorRendersOnlyTheCurrentSpecificationAndCheckpoint() throws {
        let body = """
            ### Problem

            Earlier detail remains in the Issue timeline.

            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1

            ### Proposed outcome

            Compact this current body without touching history.
            """
        let snapshot = RepositoryPolicy.Issue.Snapshot(
            coordinate: "https://github.com/swift-institute/.github/issues/174",
            revision: "\"issue-174-v1\"",
            body: body,
            native: .init(state: .open)
        )
        let expected = try RepositoryPolicy.Issue.Guard(
            revision: snapshot.revision,
            digest: snapshot.digest
        )

        let plan = try #require(
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: expected)
        )

        #expect(
            plan.body == """
                ### Kind

                Task

                ### Owner coordinate

                swift-institute/.github

                ### Status

                Active

                ### Grammar version

                1
                """
        )
        #expect(
            try RepositoryPolicy.Issue.Parser.checkpoint(plan.checkpoint).source
                == snapshot.coordinate
        )
        #expect(
            try RepositoryPolicy.Issue.Parser.checkpoint(plan.checkpoint).digest == snapshot.digest
        )
        #expect(!plan.body.contains("Earlier detail"))
        #expect(!plan.checkpoint.contains("Earlier detail"))
    }

    // Positive control: a changed entity tag OR a changed body digest must
    // refuse before any body rewrite or checkpoint can be proposed.
    @Test
    func activeRecordCompactorRefusesStaleRevisionAndDigest() throws {
        let body = """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1

            ### Problem

            Needs compaction.
            """
        let snapshot = RepositoryPolicy.Issue.Snapshot(
            coordinate: "https://github.com/swift-institute/.github/issues/174",
            revision: "\"current\"",
            body: body,
            native: .init(state: .open)
        )
        let staleRevision = try RepositoryPolicy.Issue.Guard(
            revision: "\"stale\"",
            digest: snapshot.digest
        )
        let staleDigest = try RepositoryPolicy.Issue.Guard(
            revision: snapshot.revision,
            digest: "a9993e364706816aba3e25717850c26c9cd0d89d"
        )

        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: staleRevision)
        }
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: staleDigest)
        }
    }

    @Test
    func activeRecordCompactorRefusesTerminalAndInactiveRecords() throws {
        let body = """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Blocked

            ### Grammar version

            1
            """
        let snapshot = RepositoryPolicy.Issue.Snapshot(
            coordinate: "https://github.com/swift-institute/.github/issues/174",
            revision: "\"current\"",
            body: body,
            native: .init(state: .open)
        )
        let expected = try RepositoryPolicy.Issue.Guard(
            revision: snapshot.revision,
            digest: snapshot.digest
        )

        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: expected)
        }
        let terminal = RepositoryPolicy.Issue.Snapshot(
            coordinate: snapshot.coordinate,
            revision: snapshot.revision,
            body: snapshot.body,
            native: .init(state: .completed)
        )
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: terminal, guard: expected)
        }
    }

    private func repositoryFixture(files: [String: String]) throws -> URL {
        let root =
            FileManager.default.temporaryDirectory
            .appending(path: "repository-policy-\(UUID().uuidString)")
        for (path, contents) in files {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: file)
        }
        return root
    }

    private func render(_ decision: RepositoryPolicy.Decision) -> String {
        switch decision {
        case .excluded(let reason): reason.rawValue
        case .converged: "converged"
        case .enable: "enable"
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let repository: RepositoryPolicy.Repository
        let manifestKind: String?
        let pvr: String?
        let decision: String

        enum CodingKeys: String, CodingKey {
            case name
            case repository
            case manifestKind = "manifest_kind"
            case pvr
            case decision
        }
    }
}
