@testable import PR_Transaction
import Testing

extension PRTransaction {
    @Suite struct Transaction { @Suite struct Unit {} }
}

extension PRTransaction.Transaction.Unit {
    private static let base = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private static let head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private static let old = "cccccccccccccccccccccccccccccccccccccccc"

    private static func fixture(
        task: Int = 176, taskState: String = "OPEN", planBase: String? = nil, planHead: String? = nil,
        evidenceHead: String? = nil, approvalHead: String? = nil, botApproval: Bool = true, reviewer: String = "swift-institute-bot[bot]", fullTier: String? = "success", fullTierIncluded: Bool = true, queuedRun: Bool = false, receipt: Bool = true
    ) -> PRTransaction.Snapshot {
        let task = PRTransaction.Snapshot.Issue(repository: "swift-institute/.github", number: task, state: taskState)
        let evidence = PRTransaction.Snapshot.Evidence(command: "workspace package test", result: "success", head: evidenceHead ?? head)
        let payload = PRTransaction.Snapshot.Payload(preflighted: true, head: head)
        let plan = PRTransaction.Snapshot.Plan(accepted: true, base: planBase ?? base, head: planHead ?? head, fixer: "coenttb", paths: ["Tools/PRTransaction"], evidence: [evidence], payload: payload, nextOwner: "swift-institute-bot[bot]")
        let approval = PRTransaction.Snapshot.Review(actor: reviewer, state: "APPROVED", head: approvalHead ?? head)
        let checks = [
            PRTransaction.Snapshot.Check(name: "ci-ok", head: head, conclusion: "success"),
        ] + (fullTierIncluded ? [PRTransaction.Snapshot.Check(name: "full-tier", head: head, conclusion: fullTier)] : []) + (queuedRun ? [PRTransaction.Snapshot.Check(name: "required-run", head: head, conclusion: "in_progress")] : [])
        let receipt = PRTransaction.Snapshot.Receipt(complete: receipt, head: head, issueClosed: receipt, unassigned: receipt)
        return .init(
            repository: "swift-institute/.github", pull: 181, base: base, head: head, fixer: "coenttb",
            owningTask: task, plan: plan, reviews: botApproval ? [approval] : [], checks: checks,
            unresolvedThreads: 0, merge: .init(squash: true, mergeCommit: false, rebase: false),
            receipt: receipt
        )
    }

    @Test func `accepts a complete current-head transaction`() throws { #expect(try PRTransaction.complete(fixture()) == .readyForCompletion) }
    @Test func `rejects an unrelated open issue`() { #expect(throws: PRTransaction.Error.invalidOwningTask) { try PRTransaction.review(fixture(task: 175)) } }
    @Test func `rejects a closed governing task`() { #expect(throws: PRTransaction.Error.invalidOwningTask) { try PRTransaction.review(fixture(taskState: "CLOSED")) } }
    @Test func `rejects a stale prepared base`() { #expect(throws: PRTransaction.Error.stalePlanBase(expected: base, actual: old)) { try PRTransaction.review(fixture(planBase: old)) } }
    @Test func `rejects a stale prepared head`() { #expect(throws: PRTransaction.Error.stalePlanHead(expected: head, actual: old)) { try PRTransaction.review(fixture(planHead: old)) } }
    @Test func `rejects stale evidence after a head change`() { #expect(throws: PRTransaction.Error.staleEvidence) { try PRTransaction.review(fixture(evidenceHead: old)) } }
    @Test func `rejects a nonterminal full tier`() { #expect(throws: PRTransaction.Error.nonterminalFullTier) { try PRTransaction.review(fixture(fullTier: "in_progress")) } }
    @Test func `rejects an absent full tier`() { #expect(throws: PRTransaction.Error.nonterminalFullTier) { try PRTransaction.review(fixture(fullTierIncluded: false)) } }
    @Test func `rejects an old bot approval`() { #expect(throws: PRTransaction.Error.staleBotApproval) { try PRTransaction.merge(fixture(approvalHead: old)) } }
    @Test func `rejects an absent bot approval`() { #expect(throws: PRTransaction.Error.missingBotApproval) { try PRTransaction.merge(fixture(botApproval: false)) } }
    @Test func `rejects a fixer approval`() { #expect(throws: PRTransaction.Error.reviewerIsFixer) { try PRTransaction.merge(fixture(reviewer: "coenttb")) } }
    @Test func `rejects ci completion while a required run is queued`() { #expect(throws: PRTransaction.Error.nonterminalRequiredRun) { try PRTransaction.complete(fixture(queuedRun: true)) } }
    @Test func `rejects an incomplete post-green receipt`() { #expect(throws: PRTransaction.Error.incompleteReceipt) { try PRTransaction.complete(fixture(receipt: false)) } }
}
