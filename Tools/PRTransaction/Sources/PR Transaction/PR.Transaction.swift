import Foundation

public enum PRTransaction {
    public struct Snapshot: Codable, Sendable {
        public struct Plan: Codable, Sendable {
            public let accepted: Bool
            public let head: String
            public let fixer: String
        }

        public struct Review: Codable, Sendable {
            public let actor: String
            public let state: String
            public let head: String
        }

        public struct Check: Codable, Sendable {
            public let name: String
            public let head: String
            public let conclusion: String?
        }

        public struct Issue: Codable, Sendable {
            public let repository: String
            public let state: String
        }

        public struct Merge: Codable, Sendable {
            public let squash: Bool
            public let mergeCommit: Bool
            public let rebase: Bool
        }

        public let repository: String
        public let pull: Int
        public let head: String
        public let fixer: String
        public let plan: Plan
        public let reviews: [Review]
        public let checks: [Check]
        public let unresolvedThreads: Int
        public let issues: [Issue]
        public let merge: Merge
    }

    public enum Verdict: String, Sendable {
        case readyForReview = "ready-for-bot-review"
        case readyForMerge = "ready-for-squash-merge"
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case fixer(String)
        case planNotAccepted
        case stalePlan(expected: String, actual: String)
        case missingCI
        case staleCI
        case unresolvedThreads(Int)
        case missingOpenOwningIssue
        case mergeMethod
        case missingBotApproval
        case staleBotApproval
    }

    public static func review(_ snapshot: Snapshot) throws -> Verdict {
        guard snapshot.fixer == "coenttb", snapshot.plan.fixer == snapshot.fixer else {
            throw Error.fixer(snapshot.fixer)
        }
        guard snapshot.plan.accepted else { throw Error.planNotAccepted }
        guard snapshot.plan.head == snapshot.head else {
            throw Error.stalePlan(expected: snapshot.head, actual: snapshot.plan.head)
        }
        let ci = snapshot.checks.filter { $0.name == "ci-ok" }
        guard !ci.isEmpty else { throw Error.missingCI }
        guard ci.contains(where: { $0.head == snapshot.head && $0.conclusion == "success" }) else {
            throw Error.staleCI
        }
        guard snapshot.unresolvedThreads == 0 else { throw Error.unresolvedThreads(snapshot.unresolvedThreads) }
        guard snapshot.issues.contains(where: { $0.repository == snapshot.repository && $0.state == "OPEN" }) else {
            throw Error.missingOpenOwningIssue
        }
        guard snapshot.merge.squash, !snapshot.merge.mergeCommit, !snapshot.merge.rebase else {
            throw Error.mergeMethod
        }
        return .readyForReview
    }

    public static func merge(_ snapshot: Snapshot) throws -> Verdict {
        _ = try review(snapshot)
        let approvals = snapshot.reviews.filter { $0.actor == "swift-institute-bot[bot]" && $0.state == "APPROVED" }
        guard !approvals.isEmpty else { throw Error.missingBotApproval }
        guard approvals.contains(where: { $0.head == snapshot.head }) else { throw Error.staleBotApproval }
        return .readyForMerge
    }
}
