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
