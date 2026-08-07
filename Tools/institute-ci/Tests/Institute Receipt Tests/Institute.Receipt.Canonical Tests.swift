import Byte_Primitives
import Foundation
import Institute_Receipt
import Testing

extension Institute.Receipt.Canonical {
    @Suite
    struct Test {
        @Suite
        struct Integration {}

        static func attestation(
            stage: Institute.Receipt.Stage = .preterminal,
            digest: String? = nil,
            verdict: Institute.Receipt.Verdict = .preterminal,
            jobName: String = "linux-release build+test"
        ) -> Institute.Receipt.Attestation {
            .init(
                base: .init(
                    run: .init(
                        id: 31_010_155_651, attempt: 1,
                        headSha: String(repeating: "a", count: 40),
                        event: "push", conclusion: nil,
                        repository: "swift-institute/.github",
                        workflowPath: ".github/workflows/swift-ci.yml",
                        actor: "swift-institute-bot[bot]",
                        headRepository: "swift-institute/.github",
                        headBranch: "main"),
                    subjectRepository: "swift-foundations/swift-copy-on-write",
                    subjectSha: String(repeating: "b", count: 40),
                    subjectVisibility: "public",
                    referencedWorkflows: [
                        .init(path: "b.yml", ref: "main", sha: String(repeating: "c", count: 40)),
                        .init(path: "a.yml", ref: "main", sha: String(repeating: "d", count: 40)),
                    ],
                    jobs: [
                        .init(id: 2, name: jobName, conclusion: nil, selected: true,
                              mandatory: true, runnerLabels: ["ubuntu-latest"]),
                        .init(id: 1, name: "plan", conclusion: .success, selected: true,
                              mandatory: true, runnerLabels: ["ubuntu-latest"]),
                    ],
                    jobsTotalCount: nil,
                    unmeasured: [.init(field: "linter", reason: "not exposed at capture")]),
                stage: stage,
                baseReceiptDigest: digest,
                verdict: verdict)
        }

        static func text(_ attestation: Institute.Receipt.Attestation) -> String {
            String(
                decoding: Institute.Receipt.Canonical.bytes(of: attestation).map(\.underlying),
                as: UTF8.self)
        }

        @Suite
        struct Unit {
            @Test func `object keys are emitted in code point order at every level`() {
                let rendered = Institute.Receipt.Canonical.Test.text(
                    Institute.Receipt.Canonical.Test.attestation())
                #expect(rendered.hasPrefix(#"{"actions":[],"attestationStage":"preterminal""#))
                #expect(rendered.contains(#""run":{"actor":"#))
                #expect(rendered.contains(#""subject":{"repository":"#))
                #expect(rendered.contains(#""jobs":[{"conclusion":"success","id":1,"mandatory":true"#))
            }

            @Test func `the record is one line, LF terminated, with no insignificant space`() {
                let rendered = Institute.Receipt.Canonical.Test.text(
                    Institute.Receipt.Canonical.Test.attestation())
                #expect(rendered.hasSuffix("}\n"))
                #expect(rendered.filter { $0 == "\n" }.count == 1)
                #expect(!rendered.contains(": "))
                #expect(!rendered.contains(", "))
            }

            @Test func `arrays are ordered by their declared identity key`() {
                let rendered = Institute.Receipt.Canonical.Test.text(
                    Institute.Receipt.Canonical.Test.attestation())
                let first = rendered.range(of: #""path":"a.yml""#)
                let second = rendered.range(of: #""path":"b.yml""#)
                #expect(first!.lowerBound < second!.lowerBound)
                let plan = rendered.range(of: #""name":"plan""#)
                let linux = rendered.range(of: #""name":"linux-release build+test""#)
                #expect(plan!.lowerBound < linux!.lowerBound)
            }

            @Test func `the digest names the bytes, not the value`() {
                let attestation = Institute.Receipt.Canonical.Test.attestation()
                let payload = Institute.Receipt.Canonical.bytes(of: attestation)
                #expect(
                    Institute.Receipt.Canonical.digest(of: attestation)
                        == Institute.Receipt.Canonical.digest(of: payload))
                #expect(Institute.Receipt.Canonical.digest(of: attestation).count == 64)
            }

            @Test func `a record round trips through the codec unchanged`() throws {
                let attestation = Institute.Receipt.Canonical.Test.attestation(
                    stage: .terminal, digest: String(repeating: "e", count: 64), verdict: .met)
                let payload = Institute.Receipt.Canonical.bytes(of: attestation)
                let decoded = try Institute.Receipt.Canonical.attestation(from: payload)
                #expect(Institute.Receipt.Canonical.bytes(of: decoded) == payload)
                #expect(decoded.stage == .terminal)
                #expect(decoded.verdict == .met)
            }

            @Test func `a control character is escaped and a non ASCII scalar is not`() {
                let name = "\u{03C0}\u{0001}\t\"x\""
                let rendered = Institute.Receipt.Canonical.Test.text(
                    Institute.Receipt.Canonical.Test.attestation(jobName: name))
                let expected = "\"name\":\"\u{03C0}\\u0001\\t\\\"x\\\"\""
                #expect(rendered.contains(expected))
            }
        }

        @Suite
        struct `Edge Case` {
            @Test func `a record that is not a JSON object is refused`() {
                #expect(throws: Institute.Receipt.Canonical.Error.self) {
                    try Institute.Receipt.Canonical.attestation(
                        from: Array("[]".utf8).map(Byte.init))
                }
            }

            @Test func `an unrecognised stage or verdict is refused rather than guessed`() {
                let base = Institute.Receipt.Canonical.Test.text(
                    Institute.Receipt.Canonical.Test.attestation())
                for broken in [
                    base.replacingOccurrences(of: #""preterminal","baseReceipt"#, with: #""nearly","baseReceipt"#),
                    base.replacingOccurrences(of: #""verdict":"preterminal""#, with: #""verdict":"CLEAN""#),
                ] {
                    #expect(throws: Institute.Receipt.Canonical.Error.self) {
                        try Institute.Receipt.Canonical.attestation(
                            from: Array(broken.utf8).map(Byte.init))
                    }
                }
            }
        }
    }
}
