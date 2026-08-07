import CI_Contract
import CI_Workflow
import Foundation
import Testing

@testable import CI_Validation

/// Fail-closed controls for the two drift rules.
///
/// Both rules need two things to be true, and the second is the one that
/// is easy to lose:
///
/// 1. **Zero drift against what actually ships.** This is the gate.
/// 2. **The checker can fail.** Without a positive control, a checker
///    that silently stopped scanning reports the same clean run as a
///    fully-wired file — the failure mode that left four gates in this
///    repository inert.
///
/// The controls perturb exactly one surface at a time and assert the
/// finding names that surface and that job, so a checker that just
/// reports "something is wrong somewhere" fails here.
///
/// These suites are the Swift owners of
/// `tests/test-lint-validators-weekly-drift.py` and
/// `tests/test-scheduled-workflow-alert-drift.py`, and — since neither
/// retired checker was ever invoked as a workflow step — they are also
/// the whole of both gates. The retired scripts exited `1` on findings;
/// the ported validators exit `0` and report on stdout, which is why the
/// gate has to live here and not in an exit code nobody reads.
@Suite
struct CIValidationDriftTests {
    static var repository: CI.Validation.Subject {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return .init(repository: "swift-institute/.github", root: url.path)
    }

    static func document(_ text: String) throws -> CI.Workflow.YAML.Node {
        try CI.Workflow.YAML.Parser.parse(text)
    }
}

// MARK: - LINT-VALIDATORS-WEEKLY-DRIFT

extension CIValidationDriftTests {
    /// Two scan legs, both wired across all five surfaces. Each control
    /// mutates one surface for `scan-beta` and leaves the other four —
    /// and all of `scan-alpha` — correct.
    static let weeklyBase = """
        jobs:
          scan-alpha:
            uses: ./.github/workflows/validate-alpha.yml
          scan-beta:
            uses: ./.github/workflows/validate-beta.yml
          report:
            needs:
              - scan-alpha
              - scan-beta
            if: always() && (needs.scan-alpha.result != 'skipped' || needs.scan-beta.result != 'skipped')
            steps:
              - name: Build issue body
                env:
                  RESULT_ALPHA: ${{ needs.scan-alpha.result }}
                  RESULT_BETA: ${{ needs.scan-beta.result }}
                run: |
                  for pair in "alpha:$RESULT_ALPHA" "beta:$RESULT_BETA"; do
                    echo "$pair"
                  done
                  cat > body.md <<EOF
                  ### validate-alpha
                  Job status: ${RESULT_ALPHA}.

                  ### validate-beta
                  Job status: ${RESULT_BETA}.
                  EOF
        """

    @Suite
    struct `Weekly Report Surfaces` {
        typealias Subject = CI.Validation.Drift.LintValidatorsWeekly

        @Test func `the shipped workflow has no drift`() throws {
            let findings = try Subject().findings(in: CIValidationDriftTests.repository)
            #expect(findings.isEmpty)
        }

        /// The sanity floor. If discovery ever returns nothing, the
        /// assertion above is vacuously true — a zero from the wrong root
        /// is not evidence.
        @Test func `the shipped workflow declares many scan legs`() throws {
            let text = try #require(
                try CIValidationDriftTests.repository.text(at: Subject.workflowPath))
            let document = try CIValidationDriftTests.document(text)
            let jobs = try #require(document["jobs"]?.mapping)
            #expect(jobs.textKeys.filter { $0.hasPrefix("scan-") }.count >= 10)
        }

        @Test func `the synthetic base is itself clean`() throws {
            let gaps = try Subject.gaps(
                in: CIValidationDriftTests.document(CIValidationDriftTests.weeklyBase))
            #expect(gaps.isEmpty)
        }

        @Test(arguments: [
            (
                "needs:\n      - scan-alpha\n      - scan-beta",
                "needs:\n      - scan-alpha", Subject.Surface.needs
            ),
            (
                "if: always() && (needs.scan-alpha.result != 'skipped' || needs.scan-beta.result != 'skipped')",
                "if: always() && (needs.scan-alpha.result != 'skipped')", Subject.Surface.condition
            ),
            (
                "RESULT_BETA: ${{ needs.scan-beta.result }}",
                "RESULT_BETA: ${{ needs.scan-alpha.result }}", Subject.Surface.environment
            ),
            (" \"beta:$RESULT_BETA\"", "", Subject.Surface.pairList),
            (
                "### validate-beta\n          Job status: ${RESULT_BETA}.", "",
                Subject.Surface.section
            ),
        ])
        func `removing one leg from one surface names that job and that surface`(
            _ original: String, _ replacement: String, _ surface: Subject.Surface
        ) throws {
            let text = CIValidationDriftTests.weeklyBase
                .replacingOccurrences(of: original, with: replacement)
            #expect(text != CIValidationDriftTests.weeklyBase, "the mutation must actually land")
            let gaps = try Subject.gaps(in: CIValidationDriftTests.document(text))
            let flagged = Set(gaps.filter { $0.surface == surface }.map(\.job))
            #expect(flagged.contains("scan-beta"))
            #expect(!flagged.contains("scan-alpha"))
        }

        /// The scenario the rule exists for: a leg lands with no report
        /// wiring at all and must turn every surface red, not just some.
        @Test func `an unwired leg is caught on all five surfaces`() throws {
            let text = CIValidationDriftTests.weeklyBase.replacingOccurrences(
                of: "  scan-beta:",
                with: "  scan-gamma:\n    uses: ./.github/workflows/validate-gamma.yml\n  scan-beta:"
            )
            let gaps = try Subject.gaps(in: CIValidationDriftTests.document(text))
            let surfaces = Set(gaps.filter { $0.job == "scan-gamma" }.map(\.surface))
            #expect(surfaces == Set(Subject.Surface.allCases))
        }

        @Test func `a workflow with no report job is a defect and not a clean run`() throws {
            let document = try CIValidationDriftTests.document("jobs:\n  scan-alpha:\n    uses: x\n")
            #expect(throws: CI.Validation.EnvironmentDefect.self) {
                _ = try Subject.gaps(in: document)
            }
        }

        @Test func `a run script with no heredoc falls back to the whole script`() {
            #expect(Subject.heredoc(in: "echo hello") == "echo hello")
            #expect(Subject.heredoc(in: "cat <<EOF\nbody\nEOF\ntail") == "body")
        }
    }
}

// MARK: - SCHEDULED-WORKFLOW-ALERT-DRIFT

extension CIValidationDriftTests {
    @Suite
    struct `Scheduled Workflow Watch List` {
        typealias Subject = CI.Validation.Drift.ScheduledWorkflowAlert

        static let scheduled = ["scan-alpha": "scan-alpha.yml", "scan-beta": "scan-beta.yml"]

        @Test func `the shipped watch list has no drift`() throws {
            let findings = try Subject().findings(in: CIValidationDriftTests.repository)
            #expect(findings.isEmpty)
        }

        /// The sanity floor for the same reason as above.
        @Test func `the shipped repository schedules many workflows`() throws {
            let text = try #require(
                try CIValidationDriftTests.repository.text(at: Subject.alertPath))
            let watched = try Subject.watched(in: CIValidationDriftTests.document(text))
            #expect(watched.count >= 15)
        }

        @Test func `the synthetic base is itself clean`() {
            #expect(Subject.drift(scheduled: Self.scheduled, watched: ["scan-alpha", "scan-beta"]).isEmpty)
        }

        @Test func `a scheduled workflow absent from the watch list is caught`() {
            let gaps = Subject.drift(scheduled: Self.scheduled, watched: ["scan-alpha"])
            let flagged = Set(gaps.filter { $0.surface == .missing }.map(\.name))
            #expect(flagged == ["scan-beta"])
        }

        @Test func `a watch entry naming nothing scheduled is caught`() {
            let gaps = Subject.drift(
                scheduled: Self.scheduled, watched: ["scan-alpha", "scan-beta", "scan-gamma"])
            let flagged = Set(gaps.filter { $0.surface == .stale }.map(\.name))
            #expect(flagged == ["scan-gamma"])
        }

        /// A workflow that loses its `schedule:` trigger leaves a stale
        /// entry — harmless for alerting, and evidence the list stopped
        /// tracking reality.
        @Test func `both directions are reported at once`() {
            let gaps = Subject.drift(
                scheduled: ["scan-alpha": "a.yml", "scan-delta": "d.yml"],
                watched: ["scan-alpha", "scan-beta"])
            #expect(Set(gaps.map { [$0.name, $0.surface.rawValue] })
                == [["scan-delta", "missing-from-watch-list"], ["scan-beta", "stale-watch-entry"]])
        }

        @Test func `an alert workflow without a workflows list is a defect`() throws {
            let document = try CIValidationDriftTests.document("on:\n  workflow_run:\n    types: [completed]\n")
            #expect(throws: CI.Validation.EnvironmentDefect.self) {
                _ = try Subject.watched(in: document)
            }
        }
    }
}
