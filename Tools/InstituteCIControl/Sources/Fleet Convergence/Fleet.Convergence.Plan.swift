import Fleet_Inventory

extension Fleet.Convergence {
    /// One fleet mutation plan: an ordered set of per-repository steps,
    /// each carrying its exact preimage digest and reverse payload BEFORE
    /// any write. A step without both is unplannable by construction.
    public struct Plan: Sendable, Equatable {
        public struct Step: Sendable, Equatable {
            public let repository: String
            public let coordinate: String
            /// Digest of the exact current bytes/settings read
            /// immediately before mutation; apply refuses on drift.
            public let preimageDigest: String
            /// The exact payload that restores the preimage.
            public let reversePayload: String
            /// The payload to write.
            public let payload: String

            public init(
                repository: String, coordinate: String,
                preimageDigest: String, reversePayload: String,
                payload: String
            ) {
                self.repository = repository
                self.coordinate = coordinate
                self.preimageDigest = preimageDigest
                self.reversePayload = reversePayload
                self.payload = payload
            }
        }

        public let id: String
        public let steps: [Step]

        public init(id: String, steps: [Step]) {
            self.id = id
            self.steps = steps
        }
    }
}
