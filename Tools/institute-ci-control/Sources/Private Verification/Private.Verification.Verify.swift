extension Private.Verification {
    /// The verify decision: exact-head matching and credential-boundary
    /// bookkeeping for one request. Verification runs with a read-only
    /// dependency credential that is destroyed BEFORE candidate
    /// execution; publish never sees it (K-14/K-15 shapes).
    public enum Verify {
        public enum Refusal: Sendable, Equatable {
            case headDrift(claimed: String, observed: String)
            case credentialAliveAtCandidateExecution
            case requiredOperationUnmeasured(String)
        }

        public struct Outcome: Sendable, Equatable {
            public let refusals: [Refusal]
            public var accepted: Bool { refusals.isEmpty }

            public init(refusals: [Refusal]) {
                self.refusals = refusals
            }
        }

        /// - Parameters:
        ///   - request: the typed request.
        ///   - observedHeadSha: the head actually checked out.
        ///   - credentialDestroyedBeforeCandidateExecution: attested by
        ///     the orchestration; false refuses.
        ///   - measuredOperations: operation name → measured (true) or
        ///     unmeasured (false).
        public static func decide(
            request: Request,
            observedHeadSha: String,
            credentialDestroyedBeforeCandidateExecution: Bool,
            measuredOperations: [String: Bool]
        ) -> Outcome {
            var refusals: [Refusal] = []
            if observedHeadSha != request.claimedHeadSha {
                refusals.append(.headDrift(
                    claimed: request.claimedHeadSha, observed: observedHeadSha))
            }
            if !credentialDestroyedBeforeCandidateExecution {
                refusals.append(.credentialAliveAtCandidateExecution)
            }
            for operation in request.requiredOperations
            where measuredOperations[operation] != true {
                refusals.append(.requiredOperationUnmeasured(operation))
            }
            return Outcome(refusals: refusals)
        }
    }
}
