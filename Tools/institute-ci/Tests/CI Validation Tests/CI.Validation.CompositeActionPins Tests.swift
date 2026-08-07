import CI_Contract
import Testing

@testable import CI_Validation

/// `[CI-117]` controls.
///
/// Programme corrigendum §11.1 (`swift-institute/.github#286`) makes one
/// of these mandatory: *after the change, a deliberate reversion of one
/// site to `@main` must fail a check.* The fixture corpus carries no
/// `ci-117` directory, so this suite is that control — it proves the
/// instrument **can** fail before the real-tree assertion below relies on
/// it staying silent.
///
/// Swift owner of
/// `.github/scripts/tests/test-validate-composite-action-pins.py`.
@Suite
struct CIValidationCompositeActionPinsTests {
    static let action = "swift-institute/.github/.github/actions"

    static func workflow(_ body: String) -> String {
        """
        name: fixture
        on: workflow_dispatch: {}
        jobs:
          example:
            runs-on: ubuntu-latest
            steps:
        \(body)
        """
    }

    static func findings(
        _ contents: String,
        file: String = "fixture.yml",
        repository: String = "swift-institute-test/fixture"
    ) throws -> [CI.Validation.Finding] {
        let subject = TemporaryRepository(repository: repository)
        subject.write(contents, to: ".github/workflows/\(file)")
        return try CI.Validation.CompositeActionPins().findings(in: subject.subject)
    }

    @Suite
    struct `Positive Control` {
        @Test func `a floating main reference fires and cites its line`() throws {
            let findings = try CIValidationCompositeActionPinsTests.findings(
                CIValidationCompositeActionPinsTests.workflow(
                    "      - uses: \(CIValidationCompositeActionPinsTests.action)/read-orgs@main"
                )
            )
            #expect(findings.map(\.rule) == ["CI-117"])
            #expect(findings[0].message.hasPrefix("fixture.yml:7:"))
            #expect(findings[0].message.contains("read-orgs@main"))
        }

        @Test func `a short sha is still a floating reference`() throws {
            // The class is "full 40-hex SHA", not "not literally the word
            // main".
            let findings = try CIValidationCompositeActionPinsTests.findings(
                CIValidationCompositeActionPinsTests.workflow(
                    "      - uses: \(CIValidationCompositeActionPinsTests.action)"
                        + "/read-orgs@6f73c2e"
                )
            )
            #expect(findings.map(\.rule) == ["CI-117"])
        }

        @Test func `a tag is still a floating reference`() throws {
            let findings = try CIValidationCompositeActionPinsTests.findings(
                CIValidationCompositeActionPinsTests.workflow(
                    "      - uses: \(CIValidationCompositeActionPinsTests.action)/read-orgs@v1"
                )
            )
            #expect(findings.map(\.rule) == ["CI-117"])
        }
    }

    @Suite
    struct `Negative Control` {
        @Test func `a full sha pin is silent`() throws {
            let findings = try CIValidationCompositeActionPinsTests.findings(
                CIValidationCompositeActionPinsTests.workflow(
                    "      - uses: \(CIValidationCompositeActionPinsTests.action)"
                        + "/read-orgs@6f73c2ebff00e4f05375794905926bdd7a0ca14b  # main 2026-08-04"
                )
            )
            #expect(findings.isEmpty)
        }

        @Test func `a reusable workflow at main is never this rule's finding`() throws {
            // `[CI-030]`/`REPO-ACTIONS-004` require reusable workflows to
            // stay permanently on `@main`. A finding here would mean the
            // two classes bled into each other inside the instrument, not
            // only in the surrounding prose.
            let findings = try CIValidationCompositeActionPinsTests.findings(
                """
                name: fixture
                on: workflow_dispatch: {}
                jobs:
                  example:
                    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main
                """
            )
            #expect(findings.isEmpty)
        }
    }

    @Suite
    struct Exemption {
        @Test func `the exemption is an exact pair, never a filename wildcard`() throws {
            // `lint-validators-weekly.yml` carries a typed exemption for
            // exactly (read-orgs, upsert-tracking-issue). A THIRD action
            // at `@main` in the same file is not on that list and must
            // still fire as an ordinary finding.
            let action = CIValidationCompositeActionPinsTests.action
            let findings = try CIValidationCompositeActionPinsTests.findings(
                CIValidationCompositeActionPinsTests.workflow(
                    """
                          - uses: \(action)/read-orgs@main
                          - uses: \(action)/upsert-tracking-issue@main
                          - uses: \(action)/install-system-deps@main
                    """
                ),
                file: "lint-validators-weekly.yml",
                repository: "swift-institute/.github"
            )
            #expect(findings.filter { $0.rule == "CI-117-EXEMPT" }.count == 2)
            let enforced = findings.filter { $0.rule == "CI-117" }
            #expect(enforced.count == 1)
            #expect(enforced.first?.message.contains("install-system-deps@main") == true)
        }

        @Test func `the same action in a different file is not exempt`() throws {
            let findings = try CIValidationCompositeActionPinsTests.findings(
                CIValidationCompositeActionPinsTests.workflow(
                    "      - uses: \(CIValidationCompositeActionPinsTests.action)/read-orgs@main"
                ),
                file: "some-other-workflow.yml",
                repository: "swift-institute/.github"
            )
            #expect(findings.map(\.rule) == ["CI-117"])
        }
    }

    @Suite
    struct `Real Tree` {
        @Test func `every self referential composite action reference is identity pinned`() throws {
            // The actual enforcement, run against the real committed
            // workflow set rather than a synthetic fixture. **This is the
            // assertion that turns red if a future change reverts a
            // converged site to `@main`.**
            let findings = try CI.Validation.CompositeActionPins()
                .findings(in: RepositoryUnderTest.subject)
            #expect(findings.filter { $0.rule == "CI-117" }.isEmpty)
        }
    }
}
