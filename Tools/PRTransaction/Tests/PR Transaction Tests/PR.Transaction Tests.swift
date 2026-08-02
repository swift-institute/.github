import PR_Transaction
import Testing

extension PRTransaction {
    @Suite struct Transaction {
        @Suite struct Unit {}
    }
}

extension PRTransaction.Transaction.Unit {
    private static let head = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    private static func fixture() -> PRTransaction.Snapshot {
        .init(
            repository: "swift-institute/.github",
            pull: 1,
            head: head,
            fixer: "coenttb",
            plan: .init(accepted: true, head: head, fixer: "coenttb"),
            reviews: [.init(actor: "swift-institute-bot[bot]", state: "APPROVED", head: head)],
            checks: [.init(name: "ci-ok", head: head, conclusion: "success")],
            unresolvedThreads: 0,
            issues: [.init(repository: "swift-institute/.github", state: "OPEN")],
            merge: .init(squash: true, mergeCommit: false, rebase: false)
        )
    }

    @Test func `accepts every current head control`() throws {
        #expect(try PRTransaction.merge(fixture()) == .readyForMerge)
    }

    @Test func `refuses an unaccepted plan`() {
        var snapshot = fixture()
        snapshot = .init(repository: snapshot.repository, pull: snapshot.pull, head: snapshot.head, fixer: snapshot.fixer, plan: .init(accepted: false, head: snapshot.head, fixer: snapshot.fixer), reviews: snapshot.reviews, checks: snapshot.checks, unresolvedThreads: snapshot.unresolvedThreads, issues: snapshot.issues, merge: snapshot.merge)
        #expect(throws: PRTransaction.Error.planNotAccepted) { try PRTransaction.review(snapshot) }
    }

    @Test func `refuses a stale plan head`() {
        let snapshot = fixture(stalePlan: true)
        #expect(throws: PRTransaction.Error.stalePlan(expected: head, actual: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")) { try PRTransaction.review(snapshot) }
    }

    @Test func `refuses a stale ci head`() {
        let snapshot = fixture(staleCI: true)
        #expect(throws: PRTransaction.Error.staleCI) { try PRTransaction.review(snapshot) }
    }

    @Test func `refuses a stale bot approval`() {
        let snapshot = fixture(staleApproval: true)
        #expect(throws: PRTransaction.Error.staleBotApproval) { try PRTransaction.merge(snapshot) }
    }

    private static func fixture(stalePlan: Bool = false, staleCI: Bool = false, staleApproval: Bool = false) -> PRTransaction.Snapshot {
        let snapshot = fixture()
        let old = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        return .init(repository: snapshot.repository, pull: snapshot.pull, head: snapshot.head, fixer: snapshot.fixer, plan: .init(accepted: true, head: stalePlan ? old : snapshot.head, fixer: snapshot.fixer), reviews: [.init(actor: "swift-institute-bot[bot]", state: "APPROVED", head: staleApproval ? old : snapshot.head)], checks: [.init(name: "ci-ok", head: staleCI ? old : snapshot.head, conclusion: "success")], unresolvedThreads: snapshot.unresolvedThreads, issues: snapshot.issues, merge: snapshot.merge)
    }
}
