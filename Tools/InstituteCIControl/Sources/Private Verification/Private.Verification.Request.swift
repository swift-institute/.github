extension Private.Verification {
    /// One private-verification request: an opaque request id and the
    /// exact head to verify. Public artifacts carry the request id only;
    /// the subject mapping stays on the private check surface (R33
    /// posture; private coordinates stay opaque).
    public struct Request: Sendable, Equatable {
        public enum Error: Swift.Error, Equatable {
            case emptyRequestId
            case claimedHeadNotFullSha(String)
        }

        public let requestId: String
        public let claimedHeadSha: String
        /// Required operations for the full G1 contract (R34: build,
        /// test, nested-tests, lint, inventory-digest binding).
        public let requiredOperations: [String]

        public init(
            requestId: String, claimedHeadSha: String,
            requiredOperations: [String] = ["build", "test", "nested-tests", "lint", "inventory"]
        ) throws(Error) {
            guard !requestId.isEmpty else { throw .emptyRequestId }
            guard Private.Verification.isLowercaseHex(claimedHeadSha, digits: 40) else {
                throw .claimedHeadNotFullSha(claimedHeadSha)
            }
            self.requestId = requestId
            self.claimedHeadSha = claimedHeadSha
            self.requiredOperations = requiredOperations
        }
    }
}
