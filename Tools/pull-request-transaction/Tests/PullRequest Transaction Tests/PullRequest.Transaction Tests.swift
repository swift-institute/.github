import Foundation
import Testing

@testable import PullRequest_Transaction

/// Suite shell. Nested under a dedicated `Test` namespace so the suites
/// never collide with the library types they exercise — `PostMerge` is a
/// real type in `PullRequest.Transaction`, and a same-named suite hoisted
/// beside it makes the name ambiguous at every use site.
extension PullRequest.Transaction {
    @Suite struct Test { @Suite struct Unit {} }
}

extension PullRequest.Transaction.Test.Unit {
    private var base: String { "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
    private var head: String { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    private var old: String { "cccccccccccccccccccccccccccccccccccccccc" }
    private var native: PullRequest.Transaction.Snapshot.Verification {
        .control(checks: ["fixtures", "correspondence", "scan"])
    }
    private var wave: PullRequest.Transaction.Snapshot.Verification {
        .waveMechanical(checks: ["fixtures", "correspondence", "scan"], mechanical: true)
    }

    private func fixture(
        repository: String = "swift-institute/.github",
        pull: Int = 181,
        planTargetRepository: String? = nil,
        planPull: Int? = nil,
        task: Int = 177,
        planTask: Int? = nil,
        taskRepository: String = "swift-institute/.github",
        planRepository: String? = nil,
        taskState: String = "OPEN",
        planTaskState: String? = nil,
        planBase: String? = nil,
        planHead: String? = nil,
        evidenceHead: String? = nil,
        payloadHead: String? = nil,
        approvalHead: String? = nil,
        botApproval: Bool = true,
        reviewer: String = "swift-institute-bot[bot]",
        verification: PullRequest.Transaction.Snapshot.Verification = .package,
        payloadVerification: PullRequest.Transaction.Snapshot.Verification? = nil,
        checks: [PullRequest.Transaction.Snapshot.Check]? = nil,
        queuedRun: Bool = false,
        receipt: Bool = true,
        receiptHead: String? = nil
    ) -> PullRequest.Transaction.Snapshot {
        let task = PullRequest.Transaction.Snapshot.Issue(
            repository: taskRepository,
            number: task,
            state: taskState
        )
        let planTask = PullRequest.Transaction.Snapshot.Issue(
            repository: planRepository ?? taskRepository,
            number: planTask ?? task.number,
            state: planTaskState ?? taskState
        )
        let evidence = PullRequest.Transaction.Snapshot.Evidence(
            command: "workspace package test",
            result: "success",
            head: evidenceHead ?? head
        )
        let payload = PullRequest.Transaction.Snapshot.Payload(
            preflighted: true,
            head: payloadHead ?? head,
            verification: payloadVerification ?? verification
        )
        let plan = PullRequest.Transaction.Snapshot.Plan(
            accepted: true,
            repository: planTargetRepository ?? repository,
            pull: planPull ?? pull,
            base: planBase ?? base,
            head: planHead ?? head,
            fixer: "coenttb",
            task: planTask,
            verification: verification,
            paths: ["Tools/PullRequest.Transaction"],
            evidence: [evidence],
            payload: payload,
            nextOwner: "swift-institute-bot[bot]"
        )
        let approval = PullRequest.Transaction.Snapshot.Review(
            actor: reviewer,
            state: "APPROVED",
            head: approvalHead ?? head
        )
        let packageChecks = [
            check("ci / matrix / ci-ok"),
            check("full-tier"),
        ]
        let checks =
            (checks ?? packageChecks)
            + (queuedRun ? [check("required-run", conclusion: "in_progress")] : [])
        let receipt = PullRequest.Transaction.Snapshot.Receipt(
            complete: receipt,
            head: receiptHead ?? head,
            issueClosed: receipt,
            unassigned: receipt
        )
        return .init(
            repository: repository,
            pull: pull,
            base: base,
            head: head,
            fixer: "coenttb",
            owningTask: task,
            plan: plan,
            reviews: botApproval ? [approval] : [],
            checks: checks,
            unresolvedThreads: 0,
            merge: .init(squash: true, mergeCommit: false, rebase: false),
            receipt: receipt
        )
    }

    private func check(
        _ name: String,
        revision: String? = nil,
        conclusion: String? = "success"
    ) -> PullRequest.Transaction.Snapshot.Check {
        .init(name: name, head: revision ?? head, conclusion: conclusion)
    }

    @Test func `accepts a complete current-head transaction`() throws {
        #expect(try PullRequest.Transaction.complete(fixture()) == .readyForCompletion)
    }
    @Test func `accepts a matching successor task`() throws {
        #expect(try PullRequest.Transaction.review(fixture(task: 177)) == .readyForReview)
    }
    @Test func `accepts a central task governing another Institute repository`() throws {
        #expect(
            try PullRequest.Transaction.review(
                fixture(repository: "swift-foundations/swift-tests")
            ) == .readyForReview
        )
    }
    @Test func `accepts declared native control-plane checks`() throws {
        #expect(
            try PullRequest.Transaction.review(
                fixture(
                    verification: native,
                    checks: [check("fixtures"), check("correspondence"), check("scan")]
                )
            ) == .readyForReview
        )
    }
    @Test func `serialized plan and payload retain the owning task and profile`() throws {
        let snapshot = fixture(
            verification: native,
            checks: [check("fixtures"), check("correspondence"), check("scan")]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PullRequest.Transaction.Snapshot.self, from: data)
        #expect(decoded.plan.task == decoded.owningTask)
        #expect(decoded.plan.verification == native)
        #expect(decoded.plan.payload.verification == native)
    }
    @Test func `rejects an unrelated open task snapshot`() {
        #expect(throws: PullRequest.Transaction.Error.invalidOwningTask) {
            try PullRequest.Transaction.review(fixture(task: 175, planTask: 177))
        }
    }
    @Test func `rejects a mismatched accepted-plan task`() {
        #expect(throws: PullRequest.Transaction.Error.invalidOwningTask) {
            try PullRequest.Transaction.review(fixture(task: 177, planTask: 176))
        }
    }
    @Test func `rejects a mismatched accepted-plan repository`() {
        #expect(throws: PullRequest.Transaction.Error.invalidOwningTask) {
            try PullRequest.Transaction.review(fixture(planRepository: "swift-institute/Workspace"))
        }
    }
    @Test func `rejects a plan for another target repository`() {
        #expect(throws: PullRequest.Transaction.Error.invalidTarget) {
            try PullRequest.Transaction.review(
                fixture(planTargetRepository: "swift-foundations/swift-tests")
            )
        }
    }
    @Test func `rejects a plan for another pull request`() {
        #expect(throws: PullRequest.Transaction.Error.invalidTarget) {
            try PullRequest.Transaction.review(fixture(planPull: 8))
        }
    }
    @Test func `rejects a nonpositive accepted-plan task`() {
        #expect(throws: PullRequest.Transaction.Error.invalidOwningTask) {
            try PullRequest.Transaction.review(fixture(task: 0))
        }
    }
    @Test func `rejects a closed governing task`() {
        #expect(throws: PullRequest.Transaction.Error.invalidOwningTask) {
            try PullRequest.Transaction.review(fixture(taskState: "CLOSED"))
        }
    }
    @Test func `rejects a stale prepared base`() {
        #expect(throws: PullRequest.Transaction.Error.stalePlanBase(expected: base, actual: old)) {
            try PullRequest.Transaction.review(fixture(planBase: old))
        }
    }
    @Test func `rejects a stale prepared head`() {
        #expect(throws: PullRequest.Transaction.Error.stalePlanHead(expected: head, actual: old)) {
            try PullRequest.Transaction.review(fixture(planHead: old))
        }
    }
    @Test func `rejects stale evidence after a head change`() {
        #expect(throws: PullRequest.Transaction.Error.staleEvidence) {
            try PullRequest.Transaction.review(fixture(evidenceHead: old))
        }
    }
    @Test func `rejects a stale payload after a head change`() {
        #expect(throws: PullRequest.Transaction.Error.stalePayload) {
            try PullRequest.Transaction.review(fixture(payloadHead: old))
        }
    }
    @Test func `rejects a payload prepared for another profile`() {
        #expect(throws: PullRequest.Transaction.Error.stalePayload) {
            try PullRequest.Transaction.review(fixture(payloadVerification: native))
        }
    }
    @Test func `package profile rejects an absent ci-ok`() {
        #expect(throws: PullRequest.Transaction.Error.missingCI) {
            try PullRequest.Transaction.review(fixture(checks: [check("full-tier")]))
        }
    }
    @Test func `package profile rejects the bare legacy ci-ok name`() {
        // GitHub renders the required aggregate as `ci / matrix / ci-ok`;
        // bare `ci-ok` is a name no caller path has ever produced, so it
        // must not satisfy the profile.
        #expect(throws: PullRequest.Transaction.Error.missingCI) {
            try PullRequest.Transaction.review(fixture(checks: [check("ci-ok"), check("full-tier")]))
        }
    }
    @Test func `package profile rejects the retired wrapper-compatibility ci-ok name alone`() {
        // Renamed swift-institute/.github#276 Task 3-01: `ci / ci-ok` was
        // the required context before the rename (and remains, temporarily,
        // a layer wrapper's compatibility aggregate — Task 1-04). It alone
        // no longer satisfies the `.package` profile; only `ci / matrix /
        // ci-ok` does. (Public canary/fleet overlap waves that still need
        // BOTH names use the `.control(checks:)` profile with both names
        // declared explicitly — that profile is fully general already.)
        #expect(throws: PullRequest.Transaction.Error.missingCI) {
            try PullRequest.Transaction.review(fixture(checks: [check("ci / ci-ok"), check("full-tier")]))
        }
    }
    @Test func `package profile rejects a stale ci-ok`() {
        #expect(throws: PullRequest.Transaction.Error.staleCI) {
            try PullRequest.Transaction.review(
                fixture(checks: [check("ci / matrix / ci-ok", revision: old), check("full-tier")])
            )
        }
    }
    @Test func `package profile rejects a failed ci-ok`() {
        #expect(throws: PullRequest.Transaction.Error.staleCI) {
            try PullRequest.Transaction.review(
                fixture(checks: [check("ci / matrix / ci-ok", conclusion: "failure"), check("full-tier")])
            )
        }
    }
    @Test func `package profile rejects an absent full tier`() {
        #expect(throws: PullRequest.Transaction.Error.nonterminalFullTier) {
            try PullRequest.Transaction.review(fixture(checks: [check("ci / matrix / ci-ok")]))
        }
    }
    @Test func `package profile rejects a stale full tier`() {
        #expect(throws: PullRequest.Transaction.Error.nonterminalFullTier) {
            try PullRequest.Transaction.review(
                fixture(checks: [check("ci / matrix / ci-ok"), check("full-tier", revision: old)])
            )
        }
    }
    @Test func `package profile rejects a nonterminal full tier`() {
        #expect(throws: PullRequest.Transaction.Error.nonterminalFullTier) {
            try PullRequest.Transaction.review(
                fixture(checks: [check("ci / matrix / ci-ok"), check("full-tier", conclusion: nil)])
            )
        }
    }
    @Test func `control profile rejects an empty required-check list`() {
        #expect(throws: PullRequest.Transaction.Error.profile) {
            try PullRequest.Transaction.review(fixture(verification: .control(checks: []), checks: []))
        }
    }
    @Test func `control profile rejects duplicate required-check names`() {
        #expect(throws: PullRequest.Transaction.Error.profile) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: .control(checks: ["fixtures", "fixtures"]),
                    checks: [check("fixtures")]
                )
            )
        }
    }
    @Test func `control profile rejects a missing native check`() {
        #expect(throws: PullRequest.Transaction.Error.missing("scan")) {
            try PullRequest.Transaction.review(
                fixture(verification: native, checks: [check("fixtures"), check("correspondence")])
            )
        }
    }
    @Test func `control profile rejects a stale native check`() {
        #expect(throws: PullRequest.Transaction.Error.stale("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: native,
                    checks: [
                        check("fixtures"), check("correspondence"), check("scan", revision: old),
                    ]
                )
            )
        }
    }
    @Test func `control profile rejects a failed native check`() {
        #expect(throws: PullRequest.Transaction.Error.unsuccessful("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: native,
                    checks: [
                        check("fixtures"), check("correspondence"),
                        check("scan", conclusion: "failure"),
                    ]
                )
            )
        }
    }
    // MARK: - R9: `skipped` satisfies GitHub's ruleset but not the engine
    //
    // swift-institute/.github#276 Ruling R8, independently re-verified by
    // this lane against GitHub's own documentation (fetched live,
    // docs.github.com/en/pull-requests/collaborating-with-pull-requests/
    // collaborating-on-repositories-with-code-quality-features/
    // about-status-checks): "A job that is skipped will report its status
    // as 'Success'. It will not prevent a pull request from merging, even
    // if it is a required check." — and separately, a `neutral` conclusion
    // "is treated as a success for dependent checks." So a required-status-checks
    // ruleset treats a `skipped` conclusion at the required context as
    // PASSING. So a public ordinary package repository's protected-main
    // RULESET is satisfied by a required context that concluded `skipped` —
    // e.g. its aggregate job's own `if:` condition evaluating false while
    // the workflow run still executes and posts a real check-run under the
    // required name (a live, concrete mechanism: the layer wrapper's
    // temporary `ci-ok` compatibility job carries exactly this shape today,
    // `if: ${{ always() && !github.event.repository.private }}`; and
    // swift-institute/Skills#34's `skill-hygiene / self-test` independently
    // demonstrated a control-plane repository's conditional self-test
    // reporting `skipped` at a real merged head — Ruling R10).
    //
    // Ruling R9 requires this task to ENUMERATE every merge path available
    // to a public ordinary package PR and demonstrate a `skipped` aggregate
    // is refused on each, or name the path as an open hazard with an exact
    // owner — "demonstrate, do not build": the enforcing mechanism already
    // exists (`current.allSatisfy({ $0.conclusion == "success" })` in
    // `PullRequest.Transaction.verify`, both the `.package` and `.control` cases).
    //
    // Two merge paths exist for a repository carrying the target ruleset:
    //
    //   Path A — bot-mediated: the author dispatches
    //   `review-pr-transaction.yml`, which calls exactly the function these
    //   two tests exercise. It refuses a `skipped` required check — proven
    //   below, not asserted.
    //
    //   Path B — native GitHub merge (UI "Squash and merge", `gh pr merge`,
    //   the REST `PUT .../merge` endpoint, or GitHub's own auto-merge):
    //   available to ANY actor with repository write access once the
    //   RULESET's own conditions are met — one approving review (from any
    //   reviewer; `require_code_owner_review: false`,
    //   `dismissal_restriction.enabled: false`) plus every required status
    //   check "successful" per GitHub's definition above. This path never
    //   invokes `PullRequest.Transaction.verify` at all, so it inherits none of the
    //   protection these two tests demonstrate. It is NOT closed by this
    //   task — no new enforcement is in scope (R9's explicit boundary) — and
    //   is recorded here as an OPEN HAZARD:
    //
    //     Owner: unassigned — needs a principal decision (e.g. restrict
    //     merge/write access on Institute repositories to the bot identity
    //     only, which GitHub rulesets cannot themselves express as a
    //     "require success, not skipped" predicate). Out of Task 3-01/3-02
    //     scope; raised to the coordinator/principal rather than
    //     self-assigned by this lane.
    //
    //     Severity today is bounded, not zero: `bypass_actors: []` and the
    //     single-org-member posture mean the only non-bot identity who
    //     could exploit Path B today is the same principal who could bypass
    //     enforcement by other means anyway. The gap widens the moment any
    //     additional collaborator or automation gains repository write
    //     access, which is exactly the #64 "vacuous green" class Ruling R8
    //     names one layer above the aggregate's own predicate.
    @Test func `package profile refuses a skipped required aggregate — R9 positive control on the gap`()
    {
        // If this test could not fail — if `.package` accepted `skipped`
        // the same way GitHub's ruleset does — it would prove nothing about
        // the gap (the standing fixture rule: a fixture whose passing state
        // is indistinguishable from the hazard being unreachable proves
        // nothing). It fails for the reason it exists: change `conclusion`
        // below to `"success"` and this test's `#expect(throws:)` fails.
        #expect(throws: PullRequest.Transaction.Error.staleCI) {
            try PullRequest.Transaction.review(
                fixture(
                    checks: [
                        check("ci / matrix / ci-ok", conclusion: "skipped"), check("full-tier"),
                    ]
                )
            )
        }
    }
    @Test func `control profile refuses a skipped required native check — R9 positive control on the gap`()
    {
        #expect(throws: PullRequest.Transaction.Error.unsuccessful("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: native,
                    checks: [
                        check("fixtures"), check("correspondence"),
                        check("scan", conclusion: "skipped"),
                    ]
                )
            )
        }
    }
    @Test func `control profile refuses a skipped required workspace verification check`() {
        // The same refusal, exercised against the literal private-package
        // required context, so the R9 demonstration is not read as
        // public-only.
        let workspace: PullRequest.Transaction.Snapshot.Verification = .control(
            checks: ["verification / workspace"]
        )
        #expect(throws: PullRequest.Transaction.Error.unsuccessful("verification / workspace")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: workspace,
                    checks: [check("verification / workspace", conclusion: "skipped")]
                )
            )
        }
    }
    @Test func `control profile rejects any nonterminal supplied run`() {
        #expect(throws: PullRequest.Transaction.Error.nonterminal("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: native,
                    checks: [
                        check("fixtures"), check("correspondence"), check("scan"),
                        check("scan", conclusion: nil),
                    ]
                )
            )
        }
    }

    // MARK: - reviewOnly profile (swift-institute/.github#200)
    //
    // Reserved for legitimately check-less PRs — a path outside every
    // path-filtered workflow's trigger. Fail-closed: satisfied only when the
    // exact-head check-run collection is empty; any check run present,
    // including a synthesized `full-tier` entry, is an uncited check and
    // must refuse.

    @Test func `reviewOnly profile accepts an empty exact-head check collection`() throws {
        #expect(
            try PullRequest.Transaction.review(fixture(verification: .reviewOnly, checks: []))
                == .readyForReview
        )
    }
    @Test func `reviewOnly profile rejects an existing check run at the head`() {
        #expect(throws: PullRequest.Transaction.Error.uncitedChecks) {
            try PullRequest.Transaction.review(
                fixture(verification: .reviewOnly, checks: [check("some-other-check")])
            )
        }
    }
    @Test func `reviewOnly profile rejects a full-tier run at the head`() {
        // Checks presence is what matters, not name — a full-tier run is
        // still a cited check the reviewOnly profile does not admit.
        #expect(throws: PullRequest.Transaction.Error.uncitedChecks) {
            try PullRequest.Transaction.review(
                fixture(verification: .reviewOnly, checks: [check("full-tier")])
            )
        }
    }
    @Test func `reviewOnly profile ignores a check run at a different head`() throws {
        // Belt-and-braces: the verifier re-filters by head itself rather
        // than trusting the collection to already be head-scoped, so a
        // leftover entry from a superseded head must not block an otherwise
        // check-less current head.
        #expect(
            try PullRequest.Transaction.review(
                fixture(
                    verification: .reviewOnly,
                    checks: [check("some-other-check", revision: old)]
                )
            ) == .readyForReview
        )
    }
    @Test func `serialized plan and payload retain the reviewOnly profile`() throws {
        let snapshot = fixture(verification: .reviewOnly, checks: [])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PullRequest.Transaction.Snapshot.self, from: data)
        #expect(decoded.plan.verification == .reviewOnly)
        #expect(decoded.plan.payload.verification == .reviewOnly)
    }

    // MARK: - waveMechanical profile (swift-institute/.github#211)
    //
    // The mechanical-remediation fast lane: every named check must be green
    // at the exact head, exactly like `control`, but deliberately without a
    // full-tier requirement — the mandatory post-merge full tier is the
    // deferred gate. Admissible only when `mechanical` attests the
    // mechanical-remediation class; the attestation is a second, independent
    // gate from choosing the profile.

    @Test func `wave-mode profile accepts declared mechanical checks`() throws {
        #expect(
            try PullRequest.Transaction.review(
                fixture(
                    verification: wave,
                    checks: [check("fixtures"), check("correspondence"), check("scan")]
                )
            ) == .readyForReview
        )
    }
    @Test func `wave-mode profile succeeds without a full-tier check present at the head`() throws {
        // The entire point of the fast lane: a full-tier check is not among
        // the checks supplied here, and admission still succeeds.
        #expect(
            try PullRequest.Transaction.review(
                fixture(
                    verification: wave,
                    checks: [check("fixtures"), check("correspondence"), check("scan")]
                )
            ) == .readyForReview
        )
        #expect(
            !fixture(
                verification: wave,
                checks: [check("fixtures"), check("correspondence"), check("scan")]
            ).checks.contains { $0.name == "full-tier" }
        )
    }
    @Test func `serialized plan and payload retain the wave-mode profile`() throws {
        let snapshot = fixture(
            verification: wave,
            checks: [check("fixtures"), check("correspondence"), check("scan")]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PullRequest.Transaction.Snapshot.self, from: data)
        #expect(decoded.plan.verification == wave)
        #expect(decoded.plan.payload.verification == wave)
    }
    @Test func `wave-mode profile rejects a non-mechanical declaration`() {
        // A plan cannot admit the fast lane by selecting the case alone —
        // the mechanical-class attestation must also be true.
        #expect(throws: PullRequest.Transaction.Error.profile) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: .waveMechanical(
                        checks: ["fixtures", "correspondence", "scan"],
                        mechanical: false
                    ),
                    checks: [check("fixtures"), check("correspondence"), check("scan")]
                )
            )
        }
    }
    @Test func `wave-mode profile rejects an empty required-check list`() {
        #expect(throws: PullRequest.Transaction.Error.profile) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: .waveMechanical(checks: [], mechanical: true),
                    checks: []
                )
            )
        }
    }
    @Test func `wave-mode profile rejects duplicate required-check names`() {
        #expect(throws: PullRequest.Transaction.Error.profile) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: .waveMechanical(
                        checks: ["fixtures", "fixtures"],
                        mechanical: true
                    ),
                    checks: [check("fixtures")]
                )
            )
        }
    }
    @Test func `wave-mode profile rejects a missing named check`() {
        #expect(throws: PullRequest.Transaction.Error.missing("scan")) {
            try PullRequest.Transaction.review(
                fixture(verification: wave, checks: [check("fixtures"), check("correspondence")])
            )
        }
    }
    @Test func `wave-mode profile rejects a stale named check`() {
        #expect(throws: PullRequest.Transaction.Error.stale("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: wave,
                    checks: [
                        check("fixtures"), check("correspondence"), check("scan", revision: old),
                    ]
                )
            )
        }
    }
    @Test func `wave-mode profile rejects a failed named check`() {
        #expect(throws: PullRequest.Transaction.Error.unsuccessful("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: wave,
                    checks: [
                        check("fixtures"), check("correspondence"),
                        check("scan", conclusion: "failure"),
                    ]
                )
            )
        }
    }
    @Test func `wave-mode profile rejects any nonterminal supplied run`() {
        #expect(throws: PullRequest.Transaction.Error.nonterminal("scan")) {
            try PullRequest.Transaction.review(
                fixture(
                    verification: wave,
                    checks: [
                        check("fixtures"), check("correspondence"), check("scan"),
                        check("scan", conclusion: nil),
                    ]
                )
            )
        }
    }
    @Test func `wave-mode profile still rejects an entirely empty check collection`() {
        #expect(throws: PullRequest.Transaction.Error.missing("fixtures")) {
            try PullRequest.Transaction.review(fixture(verification: wave, checks: []))
        }
    }

    // Positive controls: adding the reviewOnly and waveMechanical profiles
    // must not weaken the package or control profiles — each still refuses
    // an entirely empty exact-head check collection exactly as before.
    @Test func `package profile still rejects an entirely empty check collection`() {
        #expect(throws: PullRequest.Transaction.Error.missingCI) {
            try PullRequest.Transaction.review(fixture(checks: []))
        }
    }
    @Test func `control profile still rejects an entirely empty check collection`() {
        #expect(throws: PullRequest.Transaction.Error.missing("fixtures")) {
            try PullRequest.Transaction.review(fixture(verification: native, checks: []))
        }
    }

    @Test func `rejects an old bot approval`() {
        #expect(throws: PullRequest.Transaction.Error.staleBotApproval) {
            try PullRequest.Transaction.merge(fixture(approvalHead: old))
        }
    }
    @Test func `rejects an absent bot approval`() {
        #expect(throws: PullRequest.Transaction.Error.missingBotApproval) {
            try PullRequest.Transaction.merge(fixture(botApproval: false))
        }
    }
    @Test func `rejects a fixer approval`() {
        #expect(throws: PullRequest.Transaction.Error.reviewerIsFixer) {
            try PullRequest.Transaction.merge(fixture(reviewer: "coenttb"))
        }
    }
    @Test func `rejects ci completion while a required run is queued`() {
        #expect(throws: PullRequest.Transaction.Error.nonterminalRequiredRun) {
            try PullRequest.Transaction.complete(fixture(queuedRun: true))
        }
    }
    @Test func `rejects an incomplete post-green receipt`() {
        #expect(throws: PullRequest.Transaction.Error.incompleteReceipt) {
            try PullRequest.Transaction.complete(fixture(receipt: false))
        }
    }
    @Test func `rejects a stale post-green receipt`() {
        #expect(throws: PullRequest.Transaction.Error.incompleteReceipt) {
            try PullRequest.Transaction.complete(fixture(receiptHead: old))
        }
    }
}
