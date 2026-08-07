import GitHub

extension GitHub.Control {
    /// Deterministic retry policy for control-plane GitHub calls. The
    /// canonical packages surface rate limiting only as status; this
    /// policy owns the decision. Idempotency rule: only idempotent
    /// requests (reads, PUT-shaped settings writes with readback) may
    /// retry; non-idempotent mutations never do.
    public struct RetryPolicy: Sendable, Equatable {
        public enum Decision: Sendable, Equatable {
            case retry(afterSeconds: Int)
            case give(reason: String)
        }

        public let maximumAttempts: Int
        public let baseDelaySeconds: Int

        public init(maximumAttempts: Int = 4, baseDelaySeconds: Int = 2) {
            self.maximumAttempts = maximumAttempts
            self.baseDelaySeconds = baseDelaySeconds
        }

        /// - Parameters:
        ///   - status: HTTP status code of the failed call.
        ///   - retryAfterSeconds: parsed Retry-After, when present.
        ///   - remainingRateLimit: parsed x-ratelimit-remaining, when present.
        ///   - attempt: 1-based attempt number just completed.
        ///   - idempotent: whether the request may lawfully be repeated.
        public func decision(
            status: Int, retryAfterSeconds: Int?, remainingRateLimit: Int?,
            attempt: Int, idempotent: Bool
        ) -> Decision {
            guard idempotent else {
                return .give(reason: "non-idempotent request never retries")
            }
            guard attempt < maximumAttempts else {
                return .give(reason: "attempt budget exhausted (\(maximumAttempts))")
            }
            switch status {
            case 403, 429:
                if let retryAfterSeconds {
                    return .retry(afterSeconds: retryAfterSeconds)
                }
                if remainingRateLimit == 0 {
                    return .give(reason: "primary rate limit exhausted; wait for the window, do not hammer")
                }
                return .retry(afterSeconds: baseDelaySeconds << (attempt - 1))
            case 500, 502, 503, 504:
                return .retry(afterSeconds: baseDelaySeconds << (attempt - 1))
            default:
                return .give(reason: "status \(status) is not retryable")
            }
        }
    }
}
