public import Byte_Primitives
import FIPS_180_4

extension Institute.Receipt.Bootstrap {
    /// The complete frozen package-inputs tuple that identifies one
    /// bootstrap build. Every field participates in the digest; there is
    /// no partial or fallback key (no restore keys, CO-10).
    public struct Identity: Sendable, Equatable {
        /// Full commit SHA of swift-institute/Workspace at exact main.
        public let workspaceRevision: String
        /// Full commit SHA of swift-institute/.github (Institute CI sources).
        public let sourcesRevision: String
        /// Exact toolchain identity, e.g. the released-6.3.3 pin (R38).
        public let toolchain: String
        public let operatingSystem: String
        public let architecture: String
        /// Typed system provisioning inputs, e.g. uuid-dev (F2 record).
        public let provisioning: [String]

        public init(
            workspaceRevision: String,
            sourcesRevision: String,
            toolchain: String,
            operatingSystem: String,
            architecture: String,
            provisioning: [String]
        ) {
            self.workspaceRevision = workspaceRevision
            self.sourcesRevision = sourcesRevision
            self.toolchain = toolchain
            self.operatingSystem = operatingSystem
            self.architecture = architecture
            self.provisioning = provisioning
        }
    }
}

extension Institute.Receipt.Bootstrap.Identity {
    public enum ValidationError: Swift.Error, Sendable, Equatable {
        case revisionNotFullSha(field: String, value: String)
        case emptyField(field: String)
    }

    /// Refuses short or empty coordinates before any digest is minted;
    /// a key over an ambiguous tuple is a poisoned cache namespace.
    public func validate() throws(ValidationError) {
        for (field, value) in [
            ("workspaceRevision", workspaceRevision),
            ("sourcesRevision", sourcesRevision),
        ] {
            guard Institute.Receipt.isLowercaseHex(value.lowercased(), digits: 40) else {
                throw .revisionNotFullSha(field: field, value: value)
            }
        }
        for (field, value) in [
            ("toolchain", toolchain),
            ("operatingSystem", operatingSystem),
            ("architecture", architecture),
        ] where value.isEmpty {
            throw .emptyField(field: field)
        }
    }

    /// Canonical byte form: fixed field order, one `key=value` line per
    /// field, provisioning sorted. The digest is over these exact bytes.
    public var canonicalBytes: [Byte] {
        let lines = [
            "workspaceRevision=\(workspaceRevision)",
            "sourcesRevision=\(sourcesRevision)",
            "toolchain=\(toolchain)",
            "operatingSystem=\(operatingSystem)",
            "architecture=\(architecture)",
            "provisioning=\(provisioning.sorted().joined(separator: ","))",
        ]
        return Array(lines.joined(separator: "\n").utf8).map(Byte.init)
    }

    /// The cache key: lowercase hex SHA-256 of the canonical tuple
    /// bytes, through the R37 witness.
    public var digest: String {
        FIPS_180_4.SHA256.digest(canonicalBytes).hex
    }
}
