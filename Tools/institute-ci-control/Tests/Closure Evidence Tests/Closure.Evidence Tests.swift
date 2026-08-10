import Testing

@testable import Closure_Evidence

/// The #512 closure-evidence predicate, proved without a credential.
///
/// Every case is a recorded comment body or a recorded run fact — the
/// shapes the 2026-08-09 triage surfaced. Nothing here reads GitHub.
@Suite
struct ClosureEvidenceTests {
    typealias Citation = Closure.Evidence.Citation
    typealias Run = Closure.Evidence.Run
    typealias Verdict = Closure.Evidence.Verdict

    static let run = Citation.RunReference(
        owner: "swift-primitives", repository: "swift-bool-algebra-primitives",
        identifier: "30526232415")

    @Suite
    struct CitationTests {
        @Test func `a run URL and a fix SHA are both cited`() {
            let citation = Citation(of: """
                Fixed by 63b9d16ea1f8e2737aa0ca14b72d4b2ae1e5b6a2. Green: \
                https://github.com/swift-primitives/swift-bool-algebra-primitives/actions/runs/30526232415
                """)
            #expect(citation.runs == [ClosureEvidenceTests.run])
            #expect(citation.commits == ["63b9d16ea1f8e2737aa0ca14b72d4b2ae1e5b6a2"])
        }

        @Test func `job-page and attempt suffixes cite the same run`() {
            for suffix in ["/job/8123", "/attempts/2", ""] {
                let citation = Citation(of: """
                    (https://github.com/swift-primitives/swift-bool-algebra-primitives/actions/runs/30526232415\(suffix))
                    """)
                #expect(citation.runs == [ClosureEvidenceTests.run], "suffix \(suffix)")
            }
        }

        @Test func `the triage shape — fix pushed at SHA — cites no run`() {
            let citation = Citation(of: "Fix pushed at `fa258c9d`.")
            #expect(citation.runs.isEmpty)
            #expect(citation.commits == ["fa258c9d"])
        }

        @Test func `English words and non-run URLs are not citations`() {
            let citation = Citation(of: """
                Decades of defaced facades; see \
                https://github.com/swift-institute/.github/issues/512 instead.
                """)
            #expect(citation.runs.isEmpty)
            #expect(citation.commits.isEmpty)
        }
    }

    @Suite
    struct VerdictTests {
        @Test func `a successful run at-or-after the cited commit is compliant`() {
            let verdict = Verdict.of(
                runs: [Run(
                    reference: ClosureEvidenceTests.run, conclusion: .success,
                    orderings: ["fa258c9d": .atOrAfter])],
                unresolved: [], commitCited: true)
            #expect(verdict == .compliant(ClosureEvidenceTests.run))
        }

        @Test func `a bare SHA with no run is the triage violation`() {
            let verdict = Verdict.of(runs: [], unresolved: [], commitCited: true)
            #expect(verdict == .violation(.noRunCited(commitCited: true)))
        }

        @Test func `a cited run that failed is the strongest violation`() {
            let verdict = Verdict.of(
                runs: [
                    Run(reference: ClosureEvidenceTests.run, conclusion: .cancelled),
                    Run(reference: ClosureEvidenceTests.run, conclusion: .failure),
                ],
                unresolved: [], commitCited: true)
            #expect(verdict == .violation(.citedRunFailed(ClosureEvidenceTests.run)))
        }

        @Test func `a cancelled run is not evidence`() {
            let verdict = Verdict.of(
                runs: [Run(reference: ClosureEvidenceTests.run, conclusion: .cancelled)],
                unresolved: [], commitCited: false)
            #expect(verdict == .violation(.citedRunNotEvidence(ClosureEvidenceTests.run, "cancelled")))
        }

        @Test func `a success predating the cited commit is not evidence for it`() {
            let verdict = Verdict.of(
                runs: [Run(
                    reference: ClosureEvidenceTests.run, conclusion: .success,
                    orderings: ["fa258c9d": .before])],
                unresolved: [], commitCited: true)
            #expect(verdict == .violation(.runPredatesCitedCommit(ClosureEvidenceTests.run, commit: "fa258c9d")))
        }

        @Test func `an unresolvable citation is reported as such`() {
            let verdict = Verdict.of(runs: [], unresolved: [ClosureEvidenceTests.run], commitCited: false)
            #expect(verdict == .violation(.runUnresolvable(ClosureEvidenceTests.run)))
        }
    }
}
