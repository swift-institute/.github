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
    func instituteDefaultSurfacePolicyIsLoadableAndDenyByDefault() throws {
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: RepositoryPolicy.SurfacePolicy.instituteDefaultURL
        )

        #expect(policy.schemaVersion == 1)
        #expect(!policy.actionGrants.isEmpty)
        #expect(policy.exemptions.isEmpty)
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
