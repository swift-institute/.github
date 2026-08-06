extension Private.Verification {
    /// The public-safe envelope over a raw verification receipt. The raw
    /// receipt is destroyed after envelope construction by design; the
    /// binding digest is the surviving public coordinate. An envelope
    /// refuses construction over leaking content.
    public struct Envelope: Sendable, Equatable {
        public enum Error: Swift.Error, Equatable {
            case bindingDigestNotHex64(String)
            case leakingCoordinate(field: String)
            case operationMissing(String)
            case operationDigestUnmeasuredWithoutCause(String)
        }

        public struct Operation: Sendable, Equatable {
            public let name: String
            /// "success" | "not-applicable" | typed failure class; raw
            /// diagnostics never ride the envelope.
            public let outcome: String

            public init(name: String, outcome: String) {
                self.name = name
                self.outcome = outcome
            }
        }

        public let requestId: String
        public let bindingDigest: String
        public let workspaceSha: String
        public let policyDigest: String
        public let operations: [Operation]
        /// "unmeasured" requires a typed cause (R34 shape).
        public let inventoryDigest: String
        public let inventoryDigestCause: String?

        /// Refuses envelopes that leak machine-local paths or private
        /// names into public coordinates, miss a required operation, or
        /// carry an untyped unmeasured inventory digest.
        public init(
            requestId: String, bindingDigest: String, workspaceSha: String,
            policyDigest: String, operations: [Operation],
            inventoryDigest: String, inventoryDigestCause: String? = nil,
            requiredOperations: [String]
        ) throws(Error) {
            guard Private.Verification.isLowercaseHex(bindingDigest, digits: 64) else {
                throw .bindingDigestNotHex64(bindingDigest)
            }
            for (field, value) in [("requestId", requestId), ("policyDigest", policyDigest)] {
                for prefix in ["/Users/", "/home/", "/private/tmp/", "/tmp/", "/var/folders/"]
                where value.contains(prefix) {
                    throw .leakingCoordinate(field: field)
                }
            }
            let present = Set(operations.map(\.name))
            for required in requiredOperations where !present.contains(required) {
                throw .operationMissing(required)
            }
            if inventoryDigest == "unmeasured" && (inventoryDigestCause ?? "").isEmpty {
                throw .operationDigestUnmeasuredWithoutCause("inventoryDigest")
            }
            self.requestId = requestId
            self.bindingDigest = bindingDigest
            self.workspaceSha = workspaceSha
            self.policyDigest = policyDigest
            self.operations = operations
            self.inventoryDigest = inventoryDigest
            self.inventoryDigestCause = inventoryDigestCause
        }
    }
}
