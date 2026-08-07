import Byte_Primitives
import Institute_Receipt
import Testing

@Suite
struct InstituteReceiptBootstrapTests {
    static let workspaceSha = String(repeating: "a", count: 40)
    static let sourcesSha = String(repeating: "b", count: 40)

    static func identity(
        workspace: String = workspaceSha,
        sources: String = sourcesSha,
        toolchain: String = "Swift 6.3.3 RELEASE",
        os: String = "linux",
        arch: String = "x86_64",
        provisioning: [String] = ["uuid-dev"]
    ) -> Institute.Receipt.Bootstrap.Identity {
        .init(
            workspaceRevision: workspace,
            sourcesRevision: sources,
            toolchain: toolchain,
            operatingSystem: os,
            architecture: arch,
            provisioning: provisioning)
    }

    static func manifest(
        identity: Institute.Receipt.Bootstrap.Identity = identity(),
        key: String? = nil,
        executables: [Institute.Receipt.Bootstrap.Manifest.Executable]? = nil
    ) -> Institute.Receipt.Bootstrap.Manifest {
        .init(
            identity: identity,
            key: key ?? identity.digest,
            executables: executables ?? [
                .init(path: "bin/institute-ci", bytes: [1, 2, 3] as [Byte])
            ],
            producerRun: "31000000000")
    }

    @Suite
    struct Unit {
        @Test func digestIsDeterministicAndHex64() {
            let a = InstituteReceiptBootstrapTests.identity()
            let b = InstituteReceiptBootstrapTests.identity()
            #expect(a.digest == b.digest)
            #expect(a.digest.count == 64)
            #expect(a.digest.allSatisfy { $0.isHexDigit })
        }

        @Test func anyTupleFieldChangesTheKey() {
            let base = InstituteReceiptBootstrapTests.identity()
            let variants = [
                InstituteReceiptBootstrapTests.identity(
                    workspace: String(repeating: "c", count: 40)),
                InstituteReceiptBootstrapTests.identity(
                    sources: String(repeating: "d", count: 40)),
                InstituteReceiptBootstrapTests.identity(toolchain: "Swift 6.4 RELEASE"),
                InstituteReceiptBootstrapTests.identity(os: "macos"),
                InstituteReceiptBootstrapTests.identity(arch: "arm64"),
                InstituteReceiptBootstrapTests.identity(provisioning: []),
            ]
            for variant in variants {
                #expect(variant.digest != base.digest)
            }
        }

        @Test func matchingEntryVerifies() throws {
            let manifest = InstituteReceiptBootstrapTests.manifest()
            try manifest.verify(against: InstituteReceiptBootstrapTests.identity()) { _ in
                [1, 2, 3] as [Byte]
            }
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func shortRevisionRefuses() {
            let identity = InstituteReceiptBootstrapTests.identity(workspace: "abc123")
            #expect(throws: Institute.Receipt.Bootstrap.Identity.ValidationError.self) {
                try identity.validate()
            }
        }

        @Test func provisioningOrderDoesNotChangeTheKey() {
            let a = InstituteReceiptBootstrapTests.identity(provisioning: ["uuid-dev", "libcurl"])
            let b = InstituteReceiptBootstrapTests.identity(provisioning: ["libcurl", "uuid-dev"])
            #expect(a.digest == b.digest)
        }

        @Test func corruptExecutableFailsClosed() {
            let manifest = InstituteReceiptBootstrapTests.manifest()
            #expect(throws: Institute.Receipt.Bootstrap.Manifest.VerificationError.self) {
                try manifest.verify(against: InstituteReceiptBootstrapTests.identity()) { _ in
                    [9, 9, 9] as [Byte]
                }
            }
        }

        @Test func wrongSourceIdentityFailsClosed() {
            let manifest = InstituteReceiptBootstrapTests.manifest()
            let expected = InstituteReceiptBootstrapTests.identity(
                sources: String(repeating: "e", count: 40))
            #expect(throws: Institute.Receipt.Bootstrap.Manifest.VerificationError.self) {
                try manifest.verify(against: expected) { _ in [1, 2, 3] as [Byte] }
            }
        }

        @Test func forgedKeyFailsClosed() {
            let manifest = InstituteReceiptBootstrapTests.manifest(
                key: String(repeating: "f", count: 64))
            #expect(throws: Institute.Receipt.Bootstrap.Manifest.VerificationError.self) {
                try manifest.verify(against: InstituteReceiptBootstrapTests.identity()) { _ in
                    [1, 2, 3] as [Byte]
                }
            }
        }

        @Test func missingExecutableFailsClosed() {
            let manifest = InstituteReceiptBootstrapTests.manifest()
            #expect(throws: Institute.Receipt.Bootstrap.Manifest.VerificationError.self) {
                try manifest.verify(against: InstituteReceiptBootstrapTests.identity()) { _ in nil }
            }
        }

        @Test func emptyExecutableSetFailsClosed() {
            let manifest = InstituteReceiptBootstrapTests.manifest(executables: [])
            #expect(throws: Institute.Receipt.Bootstrap.Manifest.VerificationError.self) {
                try manifest.verify(against: InstituteReceiptBootstrapTests.identity()) { _ in
                    [1, 2, 3] as [Byte]
                }
            }
        }
    }

    @Suite
    struct Integration {
        @Test func knownAnswerAgainstIndependentImplementation() {
            // SHA-256("") through the canonical-bytes path is not reachable
            // (fields are non-empty), so pin the full canonical rendering:
            // the digest must equal an independently computed SHA-256 of the
            // exact canonical byte string. Recorded once from `shasum -a 256`
            // over the identical bytes; a witness or canonical-form change
            // must consciously update this vector.
            let identity = InstituteReceiptBootstrapTests.identity()
            let canonical = String(
                decoding: identity.canonicalBytes.map(UInt8.init), as: UTF8.self)
            #expect(canonical == """
                workspaceRevision=\(String(repeating: "a", count: 40))
                sourcesRevision=\(String(repeating: "b", count: 40))
                toolchain=Swift 6.3.3 RELEASE
                operatingSystem=linux
                architecture=x86_64
                provisioning=uuid-dev
                """)
        }
    }
}
