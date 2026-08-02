import Foundation
import Testing

@testable import PR_Transaction

extension PRTransaction {
    @Suite struct Transaction {
        @Suite struct Unit {}
        @Suite struct Integration {}
    }
}

extension PRTransaction.Transaction.Unit {
    private static let base = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private static let head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private static let old = "cccccccccccccccccccccccccccccccccccccccc"

    fileprivate static func fixture(
        task: Int = 177,
        plannedTask: Int = 177,
        taskState: String = "OPEN",
        taskType: String = "Task",
        taskReferencesPull: Bool = true,
        planBase: String? = nil,
        planHead: String? = nil,
        evidenceHead: String? = nil,
        approvalHead: String? = nil,
        botApproval: Bool = true,
        reviewer: String = "swift-institute-bot[bot]",
        fullTier: String? = "success",
        fullTierIncluded: Bool = true,
        queuedRun: Bool = false,
        receipt: Bool = true
    ) -> PRTransaction.Snapshot {
        let task = PRTransaction.Snapshot.Issue(
            repository: "swift-institute/.github",
            number: task,
            state: taskState,
            type: taskType,
            isReferencedByPull: taskReferencesPull
        )
        let evidence = PRTransaction.Snapshot.Evidence(
            command: "workspace package test",
            result: "success",
            head: evidenceHead ?? head
        )
        let payload = PRTransaction.Snapshot.Payload(preflighted: true, head: head)
        let plan = PRTransaction.Snapshot.Plan(
            accepted: true,
            base: planBase ?? base,
            head: planHead ?? head,
            fixer: "coenttb",
            task: plannedTask,
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
        let checks =
            [
                PRTransaction.Snapshot.Check(name: "ci-ok", head: head, conclusion: "success")
            ]
            + (fullTierIncluded
                ? [
                    PRTransaction.Snapshot.Check(
                        name: "full-tier",
                        head: head,
                        conclusion: fullTier
                    )
                ] : [])
            + (queuedRun
                ? [
                    PRTransaction.Snapshot.Check(
                        name: "required-run",
                        head: head,
                        conclusion: "in_progress"
                    )
                ] : [])
        let receipt = PRTransaction.Snapshot.Receipt(
            complete: receipt,
            head: head,
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

    @Test func `accepts a complete current-head transaction`() throws {
        #expect(try PRTransaction.complete(Self.fixture()) == .readyForCompletion)
    }
    @Test func `rejects an unrelated open task`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(Self.fixture(task: 178))
        }
    }
    @Test func `rejects an open lookalike issue`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(Self.fixture(taskType: "Bug"))
        }
    }
    @Test func `rejects an unlinked open task`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(Self.fixture(taskReferencesPull: false))
        }
    }
    @Test func `rejects a closed governing task`() {
        #expect(throws: PRTransaction.Error.invalidOwningTask) {
            try PRTransaction.review(Self.fixture(taskState: "CLOSED"))
        }
    }
    @Test func `rejects a stale prepared base`() {
        #expect(throws: PRTransaction.Error.stalePlanBase(expected: Self.base, actual: Self.old)) {
            try PRTransaction.review(Self.fixture(planBase: Self.old))
        }
    }
    @Test func `rejects a stale prepared head`() {
        #expect(throws: PRTransaction.Error.stalePlanHead(expected: Self.head, actual: Self.old)) {
            try PRTransaction.review(Self.fixture(planHead: Self.old))
        }
    }
    @Test func `rejects stale evidence after a head change`() {
        #expect(throws: PRTransaction.Error.staleEvidence) {
            try PRTransaction.review(Self.fixture(evidenceHead: Self.old))
        }
    }
    @Test func `rejects a nonterminal full tier`() {
        #expect(throws: PRTransaction.Error.nonterminalFullTier) {
            try PRTransaction.review(Self.fixture(fullTier: "in_progress"))
        }
    }
    @Test func `rejects an absent full tier`() {
        #expect(throws: PRTransaction.Error.nonterminalFullTier) {
            try PRTransaction.review(Self.fixture(fullTierIncluded: false))
        }
    }
    @Test func `rejects an old bot approval`() {
        #expect(throws: PRTransaction.Error.staleBotApproval) {
            try PRTransaction.merge(Self.fixture(approvalHead: Self.old))
        }
    }
    @Test func `rejects an absent bot approval`() {
        #expect(throws: PRTransaction.Error.missingBotApproval) {
            try PRTransaction.merge(Self.fixture(botApproval: false))
        }
    }
    @Test func `rejects a fixer approval`() {
        #expect(throws: PRTransaction.Error.reviewerIsFixer) {
            try PRTransaction.merge(Self.fixture(reviewer: "coenttb"))
        }
    }
    @Test func `rejects ci completion while a required run is queued`() {
        #expect(throws: PRTransaction.Error.nonterminalRequiredRun) {
            try PRTransaction.complete(Self.fixture(queuedRun: true))
        }
    }
    @Test func `rejects an incomplete post-green receipt`() {
        #expect(throws: PRTransaction.Error.incompleteReceipt) {
            try PRTransaction.complete(Self.fixture(receipt: false))
        }
    }
}

extension PRTransaction.Transaction.Integration {
    @Test func `accepts a transaction larger than process argv when read from a file`() throws {
        let snapshot = PRTransaction.Transaction.Unit.fixture()
        let review = PRTransaction.Snapshot.Review(
            actor: "swift-institute-bot[bot]",
            state: "APPROVED",
            head: snapshot.head
        )
        let large = PRTransaction.Snapshot(
            repository: snapshot.repository,
            pull: snapshot.pull,
            base: snapshot.base,
            head: snapshot.head,
            fixer: snapshot.fixer,
            owningTask: snapshot.owningTask,
            plan: snapshot.plan,
            reviews: Array(repeating: review, count: 50_000),
            checks: snapshot.checks,
            unresolvedThreads: snapshot.unresolvedThreads,
            merge: snapshot.merge,
            receipt: snapshot.receipt
        )
        let data = try JSONEncoder().encode(large)
        #expect(data.count > 2_000_000)
        let url = FileManager.default.temporaryDirectory
            .appending(component: UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try JSONDecoder().decode(
            PRTransaction.Snapshot.self,
            from: Data(contentsOf: url)
        )
        #expect(try PRTransaction.review(decoded) == .readyForReview)
    }
}
