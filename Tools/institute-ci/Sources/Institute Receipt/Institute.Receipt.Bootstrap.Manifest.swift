public import Byte_Primitives
import FIPS_180_4

extension Institute.Receipt.Bootstrap {
    /// The provenance manifest stored inside a cache entry: the identity
    /// it was produced from plus the exact digest of every executable it
    /// carries. A restored entry is trusted only after `verify` recomputes
    /// both against live bytes; any mismatch is a miss and a security
    /// record, never executed fallback (CO-10).
    public struct Manifest: Sendable, Equatable {
        public struct Executable: Sendable, Equatable {
            /// Path relative to the cache-entry root.
            public let path: String
            /// Lowercase hex SHA-256 of the executable bytes.
            public let digest: String

            public init(path: String, digest: String) {
                self.path = path
                self.digest = digest
            }

            /// Digests the executable bytes through the R37 witness, so
            /// producers never hash outside this seam.
            public init(path: String, bytes: [Byte]) {
                self.path = path
                self.digest = FIPS_180_4.SHA256.digest(bytes).hex
            }
        }

        public let identity: Identity
        /// Cache key the producer minted; must equal `identity.digest`.
        public let key: String
        public let executables: [Executable]
        /// Durable producer coordinate (trusted main run id).
        public let producerRun: String

        public init(
            identity: Identity,
            key: String,
            executables: [Executable],
            producerRun: String
        ) {
            self.identity = identity
            self.key = key
            self.executables = executables
            self.producerRun = producerRun
        }
    }
}

extension Institute.Receipt.Bootstrap.Manifest {
    public enum VerificationError: Swift.Error, Sendable, Equatable {
        case identity(Institute.Receipt.Bootstrap.Identity.ValidationError)
        case keyMismatch(recorded: String, recomputed: String)
        case identityMismatch(field: String, recorded: String, observed: String)
        case executableDigestMismatch(path: String, recorded: String, observed: String)
        case executableMissing(path: String)
        case noExecutables
    }

    /// Verifies this manifest against the identity the consumer expects
    /// and the executable bytes actually restored. `bytes` maps each
    /// manifest path to the restored file's bytes, or nil when absent.
    public func verify(
        against expected: Institute.Receipt.Bootstrap.Identity,
        bytes: (String) -> [Byte]?
    ) throws(VerificationError) {
        do throws(Institute.Receipt.Bootstrap.Identity.ValidationError) {
            try identity.validate()
        } catch {
            throw .identity(error)
        }
        guard key == identity.digest else {
            throw .keyMismatch(recorded: key, recomputed: identity.digest)
        }
        for (field, recorded, observed) in [
            ("workspaceRevision", identity.workspaceRevision, expected.workspaceRevision),
            ("sourcesRevision", identity.sourcesRevision, expected.sourcesRevision),
            ("toolchain", identity.toolchain, expected.toolchain),
            ("operatingSystem", identity.operatingSystem, expected.operatingSystem),
            ("architecture", identity.architecture, expected.architecture),
        ] where recorded != observed {
            throw .identityMismatch(field: field, recorded: recorded, observed: observed)
        }
        guard !executables.isEmpty else { throw .noExecutables }
        for executable in executables {
            guard let restored = bytes(executable.path) else {
                throw .executableMissing(path: executable.path)
            }
            let observed = FIPS_180_4.SHA256.digest(restored).hex
            guard observed == executable.digest else {
                throw .executableDigestMismatch(
                    path: executable.path,
                    recorded: executable.digest,
                    observed: observed)
            }
        }
    }
}
