extension PRTransaction.PostMerge {
    /// Classifies one watch. Any signal short of a confirmed `success` step
    /// outcome plus a confirmed run conclusion is `.lost` — never treated as
    /// `.green`, and never simply dropped. An explicit `lostReason` the
    /// dispatch step recorded before an early exit always wins over the
    /// generic step-outcome inference below it.
    public static func classify(_ watch: Watch) -> Outcome {
        if let lostReason = watch.lostReason, let reason = Outcome.Reason(rawValue: lostReason) {
            return .lost(reason: reason)
        }
        guard watch.stepOutcome == "success" else {
            return .lost(reason: watch.stepOutcome == "cancelled" ? .watchCancelled : .watchFailed)
        }
        guard let conclusion = watch.conclusion, !conclusion.isEmpty,
            let runURL = watch.runURL, !runURL.isEmpty
        else {
            // Defensive: a `success` step outcome with no recorded
            // conclusion should not happen, but must still refuse to read
            // as green.
            return .lost(reason: .runNotDiscovered)
        }
        return conclusion == "success"
            ? .green(runURL: runURL) : .red(conclusion: conclusion, runURL: runURL)
    }

    /// The full report for one watch: the classification plus, for every
    /// outcome but green, the exact Bug title and body verify-post-merge.yml
    /// files on the drained repository.
    public static func report(for watch: Watch) -> Report {
        let outcome = classify(watch)
        guard case .green = outcome else {
            return Report(
                outcome: name(of: outcome),
                title: title(for: outcome, watch: watch),
                body: body(for: outcome, watch: watch)
            )
        }
        return Report(outcome: "green", title: nil, body: nil)
    }

    private static func name(of outcome: Outcome) -> String {
        switch outcome {
        case .green: return "green"
        case .red: return "red"
        case .lost: return "lost"
        }
    }

    private static func title(for outcome: Outcome, watch: Watch) -> String {
        let short = String(watch.expectedHead.prefix(12))
        switch outcome {
        case .green:
            return ""
        case .red(let conclusion, _):
            return "Post-merge full tier \(conclusion) at \(short) (wave-mode drain)"
        case .lost(let reason):
            return "Post-merge watch lost (\(reason.rawValue)) at \(short) (wave-mode drain)"
        }
    }

    private static func body(for outcome: Outcome, watch: Watch) -> String {
        let repository = watch.repository
        let expectedHead = watch.expectedHead
        let short = String(expectedHead.prefix(12))
        let observed: String
        let expected: String
        let additional: String
        switch outcome {
        case .green:
            observed = ""
            expected = ""
            additional = ""
        case .red(let conclusion, let runURL):
            observed = """
                The mandatory post-merge full-tier verification (workflow_dispatch of `CI.yml` on `\(repository)`'s default branch at the wave-mode drained head `\(expectedHead)`) concluded `\(conclusion)`, not `success`. Run: \(runURL)
                """
            expected = """
                A wave-mode PR-tier landing (swift-institute/.github#211) requires the mandatory post-merge full tier to be green at the exact drained head. This run is red, so `\(repository)`'s default branch at `\(expectedHead)` has not been confirmed by the full-tier matrix the wave-mode profile deferred from PR-tier review.
                """
            additional = manualRevertInstruction(repository: repository, expectedHead: expectedHead)
        case .lost(let reason):
            let runNote = watch.runURL.map { " Run: \($0)" } ?? ""
            observed = """
                The mandatory post-merge full-tier verification (workflow_dispatch of `CI.yml` on `\(repository)`'s default branch at the wave-mode drained head `\(expectedHead)`) did not reach a confirmed conclusion — the watch itself was lost (\(reason.rawValue)).\(runNote)
                """
            expected = """
                A wave-mode PR-tier landing (swift-institute/.github#211) requires the mandatory post-merge full tier to be confirmed green at the exact drained head. A lost watch is not-green: `\(repository)`'s default branch at `\(expectedHead)` remains unconfirmed by the full-tier matrix the wave-mode profile deferred from PR-tier review, exactly as if the run itself had gone red.
                """
            additional = """
                **Watch lost (\(reason.rawValue)).** \(manualRevertInstruction(repository: repository, expectedHead: expectedHead)) If the drained repository's default branch has not moved past `\(expectedHead)`, re-dispatching `verify-post-merge.yml` against the same exact head is also a valid recovery.
                """
        }
        return """
            ### Observed behavior

            \(observed)

            ### Expected behavior

            \(expected)

            ### Minimal reproduction

            ```swift
            gh workflow run CI.yml --repo \(repository) --ref <default-branch-at-\(short)>
            ```

            ### Swift version

            N/A — filed automatically by verify-post-merge.yml from the run's own conclusion.

            ### Platform

            N/A — see the failing leg(s) in the run linked above for the exact platform/job that went red.

            ### Additional context

            \(additional)
            """
    }

    private static func manualRevertInstruction(repository: String, expectedHead: String) -> String {
        """
        **Manual revert required.** Full auto-revert-PR generation is not implemented in this first landing of swift-institute/.github#211 (see that Task and its landing PR for the open question on the baseline commit coordinate needed to compute "the drained commits" automatically). To revert by hand: identify the commit(s) that landed on `\(repository)`'s default branch as part of this wave drain, then on a new branch run `git revert --no-commit <oldest-drained-commit>^..\(expectedHead)`, push the branch normally, and open a revert pull request through the normal review path. Never force-push and never push directly to the default branch.
        """
    }
}
