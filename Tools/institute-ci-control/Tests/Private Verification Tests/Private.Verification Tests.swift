import Private_Verification
import Testing

@Suite
struct PrivateVerificationTests {
    static let head = String(repeating: "a", count: 40)
    static let digest = String(repeating: "b", count: 64)

    func request() throws -> Private.Verification.Request {
        try .init(requestId: "diag0005run0005", claimedHeadSha: Self.head)
    }

    func envelope(
        requestId: String = "diag0005run0005",
        inventoryDigest: String = "c0ffee", cause: String? = nil
    ) throws -> Private.Verification.Envelope {
        try .init(
            requestId: requestId, bindingDigest: Self.digest,
            workspaceSha: Self.head, policyDigest: "2026-08-04-1",
            operations: ["build", "test", "nested-tests", "lint", "inventory"]
                .map { .init(name: $0, outcome: "success") },
            inventoryDigest: inventoryDigest, inventoryDigestCause: cause,
            requiredOperations: ["build", "test", "nested-tests", "lint", "inventory"])
    }

    @Test
    func requestRefusesShortHeadAndEmptyId() {
        #expect(throws: Private.Verification.Request.Error.claimedHeadNotFullSha("abc")) {
            try Private.Verification.Request(requestId: "r", claimedHeadSha: "abc")
        }
        #expect(throws: Private.Verification.Request.Error.emptyRequestId) {
            try Private.Verification.Request(requestId: "", claimedHeadSha: Self.head)
        }
    }

    @Test
    func envelopeRefusesLeaksMissingOpsAndUntypedUnmeasured() throws {
        #expect(throws: Private.Verification.Envelope.Error.leakingCoordinate(field: "policyDigest")) {
            try Private.Verification.Envelope(
                requestId: "r", bindingDigest: Self.digest, workspaceSha: Self.head,
                policyDigest: "/Users/coen/policy", operations: [],
                inventoryDigest: "x", requiredOperations: [])
        }
        #expect(throws: Private.Verification.Envelope.Error.operationMissing("lint")) {
            try Private.Verification.Envelope(
                requestId: "r", bindingDigest: Self.digest, workspaceSha: Self.head,
                policyDigest: "p",
                operations: [.init(name: "build", outcome: "success")],
                inventoryDigest: "x", requiredOperations: ["build", "lint"])
        }
        #expect(throws: Private.Verification.Envelope.Error
            .operationDigestUnmeasuredWithoutCause("inventoryDigest")) {
            try Private.Verification.Envelope(
                requestId: "r", bindingDigest: Self.digest, workspaceSha: Self.head,
                policyDigest: "p", operations: [],
                inventoryDigest: "unmeasured", requiredOperations: [])
        }
        let typed = try envelope(inventoryDigest: "unmeasured", cause: "R34: adapter landed post-freeze")
        #expect(typed.inventoryDigestCause != nil)
    }

    @Test
    func verifyRefusesDriftLiveCredentialAndUnmeasuredOps() throws {
        let request = try request()
        let drifted = Private.Verification.Verify.decide(
            request: request,
            observedHeadSha: String(repeating: "c", count: 40),
            credentialDestroyedBeforeCandidateExecution: true,
            measuredOperations: Dictionary(uniqueKeysWithValues: request.requiredOperations.map { ($0, true) }))
        #expect(!drifted.accepted)
        let liveCredential = Private.Verification.Verify.decide(
            request: request, observedHeadSha: Self.head,
            credentialDestroyedBeforeCandidateExecution: false,
            measuredOperations: Dictionary(uniqueKeysWithValues: request.requiredOperations.map { ($0, true) }))
        #expect(liveCredential.refusals.contains(.credentialAliveAtCandidateExecution))
        let unmeasured = Private.Verification.Verify.decide(
            request: request, observedHeadSha: Self.head,
            credentialDestroyedBeforeCandidateExecution: true,
            measuredOperations: ["build": true])
        #expect(unmeasured.refusals.contains(.requiredOperationUnmeasured("lint")))
        let green = Private.Verification.Verify.decide(
            request: request, observedHeadSha: Self.head,
            credentialDestroyedBeforeCandidateExecution: true,
            measuredOperations: Dictionary(uniqueKeysWithValues: request.requiredOperations.map { ($0, true) }))
        #expect(green.accepted)
    }

    @Test
    func publishRefusesReplayStaleAndUnaccepted() throws {
        let envelope = try envelope()
        let accepted = Private.Verification.Verify.Outcome(refusals: [])
        let replay = Private.Verification.Publish.decide(
            envelope: envelope, verify: accepted,
            claimedHeadSha: Self.head, currentHeadSha: Self.head,
            previouslyPublished: ["diag0005run0005"])
        #expect(replay.refusals.contains(.replay(requestId: "diag0005run0005")))
        let stale = Private.Verification.Publish.decide(
            envelope: envelope, verify: accepted,
            claimedHeadSha: Self.head,
            currentHeadSha: String(repeating: "d", count: 40),
            previouslyPublished: [])
        #expect(!stale.permitted)
        let unaccepted = Private.Verification.Publish.decide(
            envelope: envelope,
            verify: .init(refusals: [.credentialAliveAtCandidateExecution]),
            claimedHeadSha: Self.head, currentHeadSha: Self.head,
            previouslyPublished: [])
        #expect(unaccepted.refusals.contains(.verifyNotAccepted))
        let green = Private.Verification.Publish.decide(
            envelope: envelope, verify: accepted,
            claimedHeadSha: Self.head, currentHeadSha: Self.head,
            previouslyPublished: [])
        #expect(green.permitted)
    }
}
