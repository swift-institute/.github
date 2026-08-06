extension Private.Verification {
    /// The publish decision: whether a validated envelope may become a
    /// public check. Replay and stale-head publication refuse (K-15);
    /// the publisher holds a checks-write token only, never the
    /// dependency credential.
    public enum Publish {
        public enum Refusal: Sendable, Equatable {
            case replay(requestId: String)
            case staleHead(envelopeHead: String, currentHead: String)
            case verifyNotAccepted
        }

        public struct Outcome: Sendable, Equatable {
            public let refusals: [Refusal]
            public var permitted: Bool { refusals.isEmpty }

            public init(refusals: [Refusal]) {
                self.refusals = refusals
            }
        }

        /// - Parameters:
        ///   - envelope: the validated public-safe envelope.
        ///   - verify: the verify outcome for the same request.
        ///   - claimedHeadSha: the head the envelope attests.
        ///   - currentHeadSha: the subject's current head at publish; a
        ///     drifted head refuses (stale publication).
        ///   - previouslyPublished: request ids already published; a
        ///     repeat is a replay.
        public static func decide(
            envelope: Envelope,
            verify: Verify.Outcome,
            claimedHeadSha: String,
            currentHeadSha: String,
            previouslyPublished: Set<String>
        ) -> Outcome {
            var refusals: [Refusal] = []
            if previouslyPublished.contains(envelope.requestId) {
                refusals.append(.replay(requestId: envelope.requestId))
            }
            if claimedHeadSha != currentHeadSha {
                refusals.append(.staleHead(
                    envelopeHead: claimedHeadSha, currentHead: currentHeadSha))
            }
            if !verify.accepted {
                refusals.append(.verifyNotAccepted)
            }
            return Outcome(refusals: refusals)
        }
    }
}
