import CI_Contract

extension CI.Validation.ThinCallers {
    /// The finding prose, byte-for-byte as the retired validator emitted
    /// it.
    ///
    /// Gathered here for one reason: the port's single measured
    /// comparison is TSV byte-identity against the retired script, and the
    /// message is the third column. Prose scattered through the predicates
    /// is prose that gets improved in passing, which turns a measured
    /// difference into an unreadable diff.
    ///
    /// Every message names the rule it serves and the repair, because a
    /// finding is read by whoever has to fix the caller.
    public enum Message {
        public static let inlineRunsOn = """
            .github/workflows/ci.yml contains inline `runs-on:` — per \
            [GH-REPO-074] this MUST be a thin caller delegating to a centralized \
            reusable workflow via `uses:`. Reference shape: \
            swift-carrier-primitives/.github/workflows/ci.yml.
            """

        public static let inlineSteps = """
            .github/workflows/ci.yml contains inline `steps:` — per \
            [GH-REPO-074] the canonical CI workflow MUST NOT contain inline \
            job-step definitions; delegate via `uses:` to a centralized reusable \
            workflow.
            """

        public static let noReusable = """
            .github/workflows/ci.yml does not reference any reusable via `uses:` \
            — per [GH-REPO-074] thin callers MUST delegate to a centralized \
            reusable workflow (e.g., `uses: \
            <layer>/.github/.github/workflows/swift-ci.yml@main`).
            """

        public static func standaloneWorkflow(_ name: String) -> String {
            """
            .github/workflows/\(name) exists as a standalone file — per \
            [GH-REPO-074] (post-2026-05-10 consolidation) the format and lint \
            legs are absorbed into the layer wrapper's universal matrix via \
            swift-ci.yml. Delete the standalone file.
            """
        }

        public static func unpinnedReference(_ reference: Line.Reference) -> String {
            """
            .github/workflows/ci.yml `uses: \(reference.path)@\(reference.ref)` — \
            per [CI-030] intra-Institute reusable refs MUST pin to `@main` during \
            active dev. Tag pins (`@v1`, `@v1.0.0`) and SHA pins are forbidden \
            until the reusable surface stabilizes at `@v1` per \
            `swift-institute/Research/ci-centralization-strategy.md`.
            """
        }

        public static func sameOrganizationExplicit(job: String) -> String {
            """
            .github/workflows/ci.yml job `\(job)` invokes an intra-Institute \
            reusable with explicit `secrets:` forwarding — per the #92 ruling \
            same-org callers MUST use `secrets: inherit`; explicit per-secret \
            sets are forbidden. Org-level secrets per [CI-060] obviate explicit \
            forwarding, which drifts at every new secret addition.
            """
        }

        public static func sameOrganizationOmitted(job: String) -> String {
            """
            .github/workflows/ci.yml job `\(job)` invokes an intra-Institute \
            reusable without `secrets: inherit` — per [CI-059] and the #92 ruling \
            every same-org `uses:` invocation of an intra-Institute reusable MUST \
            include `secrets: inherit` (single canonical shape per [CI-031], \
            universal across consumers regardless of dependency-graph visibility).
            """
        }

        public static func crossOrganizationInherit(job: String) -> String {
            """
            .github/workflows/ci.yml job `\(job)` is sub-org-hosted and uses \
            `secrets: inherit` — per the #92 ruling this hop is cross-org and \
            inherit silently delivers no org secrets ([CI-109]). Replace with the \
            explicit `secrets:` block forwarding \(closedSet) as \
            `NAME: ${{ secrets.NAME }}` lines.
            """
        }

        public static func crossOrganizationMissing(job: String, names: [String]) -> String {
            """
            .github/workflows/ci.yml job `\(job)` is sub-org-hosted and \
            explicit-forwards secrets but is missing \(names.joined(separator: ", ")) — \
            per the #92 ruling the closed credential set MUST be forwarded in full \
            (`NAME: ${{ secrets.NAME }}` per name; [CI-109]).
            """
        }

        public static func crossOrganizationExtra(job: String, names: [String]) -> String {
            """
            .github/workflows/ci.yml job `\(job)` is sub-org-hosted and forwards \
            \(names.joined(separator: ", ")) beyond the closed set — per the #92 \
            ruling the cross-org transport is exactly \(closedSet); widening it is \
            a ruling, not a caller edit.
            """
        }

        public static func crossOrganizationOmitted(job: String) -> String {
            """
            .github/workflows/ci.yml job `\(job)` is sub-org-hosted and invokes an \
            intra-Institute reusable without any `secrets:` — per the #92 ruling \
            it MUST explicit-forward \(closedSet) ([CI-109]; inherit is \
            same-org-only and omission leaves resolve uncredentialed).
            """
        }

        /// The message deliberately still names `generate-caller.py`, the
        /// script this port deletes. Byte-identity with the retired output
        /// is the unwaived floor of the single measured comparison, and
        /// re-pointing it at `repository-policy render-caller` in the same
        /// change would spend that floor on a prose edit. It is a one-line
        /// follow-up, recorded on the PR rather than smuggled in here.
        public static func integratedDocs(_ value: String) -> String {
            """
            .github/workflows/ci.yml 'ci' job `with: integrated-docs: \(value)` — \
            TX10 (swift-institute/.github#276) deleted this temporary migration \
            input from the universal reusable and every layer wrapper; GitHub \
            rejects an undeclared input, so this caller fails at run time. \
            Regenerate it with generate-caller.py.
            """
        }

        static var closedSet: String {
            CI.Validation.ThinCallers.crossOrganizationSecrets.joined(separator: ", ")
        }
    }
}
