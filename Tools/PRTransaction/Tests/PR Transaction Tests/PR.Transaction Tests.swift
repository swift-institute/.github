import Foundation
import Testing

@testable import PR_Transaction

extension PRTransaction {
    @Suite struct Transaction { @Suite struct Unit {} }
}

extension PRTransaction.Transaction.Unit {
    private var base: String { "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
    private var head: String { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    private var old: String { "cccccccccccccccccccccccccccccccccccccccc" }
    private var native: PRTransaction.Snapshot.Verification {
        .control(checks: ["fixtures", "correspondence", "scan"])
    }

    private func fixture(
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
        verification: PRTransaction.Snapshot.Verification = .package,
        payloadVerification: PRTransaction.Snapshot.Verification? = nil,
        checks: [PRTransaction.Snapshot.Check]? = nil,
        queuedRun: Bool = false,
        receipt: Bool = true,
        receiptHead: String? = nil
    ) -> PRTransaction.Snapshot {
        let task = PRTransaction.Snapshot.Issue(
            repository: taskRepository,
            number: task,
            state: taskState
        )
        let planTask = PRTransaction.Snapshot.Issue(
            repository: planRepository ?? taskRepository,
            number: planTask ?? task.number,
            state: planTaskState ?? taskState
        )
        let evidence = PRTransaction.Snapshot.Evidence(
            command: "workspace package test",
            result: "success",
            head: evidenceHead ?? head
        )
        let payload = PRTransaction.Snapshot.Payload(
            preflighted: true,
            head: payloadHead ?? head,
            verification: payloadVerification ?? verification
        )
        let plan = PRTransaction.Snapshot.Plan(
            accepted: true,
            base: planBase ?? base,
            head: planHead ?? head,
            fixer: "coenttb",
            task: planTask,
            verification: verification,
            paths: ["Tools/PRTransaction"],
            evidence: [evidence],
            payload: payload,
            nextOwner: "swift-institute-bot[bot]"
        )
        let approval = PRTransaction.Snapshot.Review(
            actor: reviewer,
            state: "APPROVED",
            head: approvalHead ?? head
        )
        let packageChecks = [
            check("ci-ok"),
            check("full-tier"),
        ]
        let checks =
            (checks ?? packageChecks)
            + (queuedRun ? [check("required-run", conclusion: "in_progress")] : [])
        let receipt = PRTransaction.Snapshot.Receipt(
            complete: receipt,
            head: receiptHead ?? head,
            issueClosed: receipt,
            unassigned: receipt
        )
        return .init(
            repository: "swift-institute/.github",
            pull: 181,
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
    ) -> PRTransaction.Snapshot.Check {
        .init(name: name, head: revision ?? head, conclusion: conclusion)
    }

    @Test func `accepts a complete current-head transaction`() throws {
        #expect(try PRTransaction.complete(fixture()) == .readyForCompletion)
    }
    @Test func `accepts a matching successor task`() throws {
        #expect(try PRTransaction.review(fixture(task: 177)) == .readyForReview)
    }
    @Test func `accepts declared native control-plane checks`() throws {
        #expect(
            try PRTransaction.review(
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
        let decoded = try JSONDecoder().decode(PRTransaction.Snapshot.self, from: data)
        #expect(decoded.plan.task == decoded.owningTask)
        #expect(decoded.plan.verification == native)
        #expect(decoded.plan.payload.verification == native)
    }
    @Test func `rejects an unrelated open task snapshot`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(fixture(task: 175, planTask: 177))
        }
    }
    @Test func `rejects a mismatched accepted-plan task`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(fixture(task: 177, planTask: 176))
        }
    }
    @Test func `rejects a mismatched accepted-plan repository`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(fixture(planRepository: "swift-institute/Workspace"))
        }
    }
    @Test func `rejects a nonpositive accepted-plan task`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(fixture(task: 0))
        }
    }
    @Test func `rejects a closed governing task`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(fixture(taskState: "CLOSED"))
        }
    }
    @Test func `rejects a stale prepared base`() {
        #expect(throws: PRTransaction.Error.stalePlanBase(expected: base, actual: old)) {
            try PRTransaction.review(fixture(planBase: old))
        }
    }
    @Test func `rejects a stale prepared head`() {
        #expect(throws: PRTransaction.Error.stalePlanHead(expected: head, actual: old)) {
            try PRTransaction.review(fixture(planHead: old))
        }
    }
    @Test func `rejects stale evidence after a head change`() {
        #expect(throws: PRTransaction.Error.staleEvidence) {
            try PRTransaction.review(fixture(evidenceHead: old))
        }
    }
    @Test func `rejects a stale payload after a head change`() {
        #expect(throws: PRTransaction.Error.stalePayload) {
            try PRTransaction.review(fixture(payloadHead: old))
        }
    }
    @Test func `rejects a payload prepared for another profile`() {
        #expect(throws: PRTransaction.Error.stalePayload) {
            try PRTransaction.review(fixture(payloadVerification: native))
        }
    }
    @Test func `package profile rejects an absent ci-ok`() {
        #expect(throws: PRTransaction.Error.missingCI) {
            try PRTransaction.review(fixture(checks: [check("full-tier")]))
        }
    }
    @Test func `package profile rejects a stale ci-ok`() {
        #expect(throws: PRTransaction.Error.staleCI) {
            try PRTransaction.review(
                fixture(checks: [check("ci-ok", revision: old), check("full-tier")])
            )
        }
    }
    @Test func `package profile rejects a failed ci-ok`() {
        #expect(throws: PRTransaction.Error.staleCI) {
            try PRTransaction.review(
                fixture(checks: [check("ci-ok", conclusion: "failure"), check("full-tier")])
            )
        }
    }
    @Test func `package profile rejects an absent full tier`() {
        #expect(throws: PRTransaction.Error.nonterminalFullTier) {
            try PRTransaction.review(fixture(checks: [check("ci-ok")]))
        }
    }
    @Test func `package profile rejects a stale full tier`() {
        #expect(throws: PRTransaction.Error.nonterminalFullTier) {
            try PRTransaction.review(
                fixture(checks: [check("ci-ok"), check("full-tier", revision: old)])
            )
        }
    }
    @Test func `package profile rejects a nonterminal full tier`() {
        #expect(throws: PRTransaction.Error.nonterminalFullTier) {
            try PRTransaction.review(
                fixture(checks: [check("ci-ok"), check("full-tier", conclusion: nil)])
            )
        }
    }
    @Test func `control profile rejects an empty required-check list`() {
        #expect(throws: PRTransaction.Error.profile) {
            try PRTransaction.review(fixture(verification: .control(checks: []), checks: []))
        }
    }
    @Test func `control profile rejects duplicate required-check names`() {
        #expect(throws: PRTransaction.Error.profile) {
            try PRTransaction.review(
                fixture(
                    verification: .control(checks: ["fixtures", "fixtures"]),
                    checks: [check("fixtures")]
                )
            )
        }
    }
    @Test func `control profile rejects a missing native check`() {
        #expect(throws: PRTransaction.Error.missing("scan")) {
            try PRTransaction.review(
                fixture(verification: native, checks: [check("fixtures"), check("correspondence")])
            )
        }
    }
    @Test func `control profile rejects a stale native check`() {
        #expect(throws: PRTransaction.Error.stale("scan")) {
            try PRTransaction.review(
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
        #expect(throws: PRTransaction.Error.unsuccessful("scan")) {
            try PRTransaction.review(
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
    @Test func `control profile rejects any nonterminal supplied run`() {
        #expect(throws: PRTransaction.Error.nonterminal("scan")) {
            try PRTransaction.review(
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
    @Test func `rejects an old bot approval`() {
        #expect(throws: PRTransaction.Error.staleBotApproval) {
            try PRTransaction.merge(fixture(approvalHead: old))
        }
    }
    @Test func `rejects an absent bot approval`() {
        #expect(throws: PRTransaction.Error.missingBotApproval) {
            try PRTransaction.merge(fixture(botApproval: false))
        }
    }
    @Test func `rejects a fixer approval`() {
        #expect(throws: PRTransaction.Error.reviewerIsFixer) {
            try PRTransaction.merge(fixture(reviewer: "coenttb"))
        }
    }
    @Test func `rejects ci completion while a required run is queued`() {
        #expect(throws: PRTransaction.Error.nonterminalRequiredRun) {
            try PRTransaction.complete(fixture(queuedRun: true))
        }
    }
    @Test func `rejects an incomplete post-green receipt`() {
        #expect(throws: PRTransaction.Error.incompleteReceipt) {
            try PRTransaction.complete(fixture(receipt: false))
        }
    }
    @Test func `rejects a stale post-green receipt`() {
        #expect(throws: PRTransaction.Error.incompleteReceipt) {
            try PRTransaction.complete(fixture(receiptHead: old))
        }
    }
}
