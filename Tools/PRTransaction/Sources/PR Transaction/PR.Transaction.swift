import Foundation

public enum PRTransaction {
    public struct Snapshot: Codable, Sendable {
        public struct Plan: Codable, Sendable {
            public let accepted: Bool
            /// The exact target repository accepted by this plan.
            public let repository: String
            /// The exact target pull request accepted by this plan.
            public let pull: Int
            public let base: String
            public let head: String
            public let fixer: String
            /// The exact open owning-Issue coordinate accepted by this plan.
            public let task: Issue
            /// The required-check profile accepted at this plan's exact head.
            public let verification: Verification
            public let paths: [String]
            public let evidence: [Evidence]
            public let payload: Payload
            public let nextOwner: String
        }

        public struct Evidence: Codable, Sendable {
            public let command: String
            public let result: String
            public let head: String
        }

        public struct Payload: Codable, Sendable {
            public let preflighted: Bool
            public let head: String
            /// The required-check profile included in the preflighted payload.
            public let verification: Verification
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

        public struct Issue: Codable, Equatable, Sendable {
            public let repository: String
            public let number: Int
            public let state: String
        }

        public struct Merge: Codable, Sendable {
            public let squash: Bool
            public let mergeCommit: Bool
            public let rebase: Bool
        }

        public struct Receipt: Codable, Sendable {
            public let complete: Bool
            public let head: String
            public let issueClosed: Bool
            public let unassigned: Bool
        }

        public let repository: String
        public let pull: Int
        public let base: String
        public let head: String
        public let fixer: String
        public let owningTask: Issue
        public let plan: Plan
        public let reviews: [Review]
        public let checks: [Check]
        public let unresolvedThreads: Int
        public let merge: Merge
        public let receipt: Receipt
    }

    public enum Verdict: String, Sendable {
        case readyForReview = "ready-for-bot-review"
        case readyForMerge = "ready-for-squash-merge"
        case readyForCompletion = "ready-for-post-green-receipt"
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case fixer(String)
        case reviewerIsFixer
        case planNotAccepted
        case invalidTarget
        case stalePlanBase(expected: String, actual: String)
        case stalePlanHead(expected: String, actual: String)
        case missingPaths
        case missingEvidence
        case staleEvidence
        case payloadNotPreflighted
        case stalePayload
        case missingNextOwner
        case missingCI
        case nonterminalFullTier
        case staleCI
        case unresolvedThreads(Int)
        case invalidOwningTask
        case mergeMethod
        case missingBotApproval
        case staleBotApproval
        case nonterminalRequiredRun
        case incompleteReceipt
        case profile
        case incomplete(String)
        case missing(String)
        case stale(String)
        case nonterminal(String)
        case unsuccessful(String)
        case uncitedChecks
    }

    public static func review(_ snapshot: Snapshot) throws -> Verdict {
        guard snapshot.fixer == "coenttb", snapshot.plan.fixer == snapshot.fixer else {
            throw Error.fixer(snapshot.fixer)
        }
        guard snapshot.plan.accepted else { throw Error.planNotAccepted }
        guard snapshot.plan.repository == snapshot.repository,
            snapshot.plan.pull == snapshot.pull,
            !snapshot.repository.isEmpty,
            snapshot.pull > 0
        else {
            throw Error.invalidTarget
        }
        guard snapshot.plan.base == snapshot.base else {
            throw Error.stalePlanBase(expected: snapshot.base, actual: snapshot.plan.base)
        }
        guard snapshot.plan.head == snapshot.head else {
            throw Error.stalePlanHead(expected: snapshot.head, actual: snapshot.plan.head)
        }
        guard !snapshot.plan.paths.isEmpty else { throw Error.missingPaths }
        guard !snapshot.plan.evidence.isEmpty,
            snapshot.plan.evidence.allSatisfy({ !$0.command.isEmpty && $0.result == "success" })
        else {
            throw Error.missingEvidence
        }
        guard snapshot.plan.evidence.allSatisfy({ $0.head == snapshot.head }) else {
            throw Error.staleEvidence
        }
        guard snapshot.plan.payload.preflighted else { throw Error.payloadNotPreflighted }
        guard snapshot.plan.payload.head == snapshot.head,
            snapshot.plan.payload.verification == snapshot.plan.verification
        else { throw Error.stalePayload }
        guard snapshot.plan.nextOwner == "swift-institute-bot[bot]" else {
            throw Error.missingNextOwner
        }
        guard snapshot.plan.task.number > 0,
            snapshot.plan.task.state == "OPEN",
            snapshot.owningTask == snapshot.plan.task
        else {
            throw Error.invalidOwningTask
        }
        try verify(snapshot)
        guard snapshot.unresolvedThreads == 0 else {
            throw Error.unresolvedThreads(snapshot.unresolvedThreads)
        }
        guard snapshot.merge.squash, !snapshot.merge.mergeCommit, !snapshot.merge.rebase else {
            throw Error.mergeMethod
        }
        return .readyForReview
    }

    public static func merge(_ snapshot: Snapshot) throws -> Verdict {
        _ = try review(snapshot)
        guard
            !snapshot.reviews.contains(where: {
                $0.state == "APPROVED" && $0.actor == snapshot.fixer
            })
        else {
            throw Error.reviewerIsFixer
        }
        let approvals = snapshot.reviews.filter {
            $0.actor == "swift-institute-bot[bot]" && $0.state == "APPROVED"
        }
        guard !approvals.isEmpty else { throw Error.missingBotApproval }
        guard approvals.contains(where: { $0.head == snapshot.head }) else {
            throw Error.staleBotApproval
        }
        return .readyForMerge
    }

    public static func complete(_ snapshot: Snapshot) throws -> Verdict {
        _ = try merge(snapshot)
        guard
            snapshot.checks.allSatisfy({
                ["success", "failure", "cancelled", "skipped"].contains($0.conclusion ?? "")
            })
        else {
            throw Error.nonterminalRequiredRun
        }
        guard snapshot.receipt.complete, snapshot.receipt.head == snapshot.head,
            snapshot.receipt.issueClosed, snapshot.receipt.unassigned
        else {
            throw Error.incompleteReceipt
        }
        return .readyForCompletion
    }
}
