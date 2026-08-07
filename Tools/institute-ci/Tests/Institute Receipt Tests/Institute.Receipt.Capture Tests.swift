import Byte_Primitives
import Foundation
import Institute_Receipt
import Testing

/// The effective-runtime-receipt subsystem (TX7 receipt contract,
/// swift-institute/.github#276 §8.9; predicates P19/P20), ported from
/// `.github/scripts/tests/test-effective-runtime-receipt.py`.
///
/// The P20 mandatory negative control lives here: the empty-referenced-
/// workflows case must be accepted by the historical false-success shape
/// and refused by the shipped one. A control that only proves the fix
/// works proves nothing about whether the defect could still be shipped.
extension Institute.Receipt.Capture {
    @Suite
    struct Test {
        @Suite
        struct Integration {}

        static let sha = "9a049de38e4ab925ce3edefdf1cd1b67428565c5"
        static let subjectSha = String(repeating: "a", count: 40)
        static let gating = ["plan", "macos-release"]

        static func run(referencedWorkflows: [[String: Any]]? = nil, headSha: String? = nil)
            -> [String: Any]
        {
            [
                "id": 31_000_000_001,
                "run_attempt": 1,
                "conclusion": NSNull(),
                "event": "workflow_dispatch",
                "path": ".github/workflows/swift-ci.yml",
                "head_sha": headSha ?? sha,
                "head_branch": "main",
                "repository": ["full_name": "swift-institute/.github"],
                "head_repository": ["full_name": "swift-institute/.github"],
                "actor": ["login": "swift-institute-bot[bot]"],
                "referenced_workflows": referencedWorkflows ?? [
                    [
                        "path": "swift-institute/.github/.github/workflows/swift-ci.yml@refs/heads/main",
                        "ref": "refs/heads/main",
                        "sha": "86631ee613f0032c5d395313a2e3253840fb1673",
                    ]
                ],
            ]
        }

        static var jobs: [[String: Any]] {
            [
                ["id": 1, "name": "plan", "conclusion": "success", "labels": ["ubuntu-latest"]],
                ["id": 2, "name": "macos-release build+test", "conclusion": NSNull(),
                 "labels": ["macos-26"]],
                ["id": 3, "name": "lint-yaml advisory", "conclusion": "skipped",
                 "labels": ["ubuntu-latest"]],
            ]
        }

        static func capture(
            run: [String: Any]? = nil,
            jobs: [[String: Any]]? = nil,
            emptyChain: Institute.Receipt.Capture.EmptyChain = .refused
        ) -> Institute.Receipt.Attestation {
            Institute.Receipt.Capture.attestation(
                run: run ?? Self.run(),
                jobs: jobs ?? Self.jobs,
                plannedGating: gating,
                subjectRepository: "swift-foundations/swift-copy-on-write",
                subjectSha: subjectSha,
                subjectVisibility: "public",
                emptyChain: emptyChain)
        }

        @Suite
        struct Unit {
            @Test func `the same inputs canonicalize to the same bytes and digest`() {
                let first = Institute.Receipt.Capture.Test.capture()
                let second = Institute.Receipt.Capture.Test.capture()
                #expect(
                    Institute.Receipt.Canonical.bytes(of: first)
                        == Institute.Receipt.Canonical.bytes(of: second))
                #expect(
                    Institute.Receipt.Canonical.digest(of: first)
                        == Institute.Receipt.Canonical.digest(of: second))
            }

            @Test func `a changed input changes the digest`() {
                let original = Institute.Receipt.Capture.Test.capture()
                let altered = Institute.Receipt.Capture.Test.capture(
                    run: Institute.Receipt.Capture.Test.run(
                        headSha: String(repeating: "b", count: 40)))
                #expect(
                    Institute.Receipt.Canonical.digest(of: original)
                        != Institute.Receipt.Canonical.digest(of: altered))
            }

            @Test func `the record carries exactly the declared thirteen top level keys`() throws {
                let payload = Institute.Receipt.Canonical.bytes(
                    of: Institute.Receipt.Capture.Test.capture())
                let data = Data(payload.map(\.underlying))
                let record = try #require(
                    try JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(
                    record.keys.sorted() == [
                        "actions", "attestationStage", "baseReceiptDigest", "containers",
                        "jobs", "linter", "referencedWorkflows", "revisions", "run",
                        "schemaVersion", "subject", "unmeasured", "verdict",
                    ])
            }

            @Test func `every null preterminal conclusion is paired with an unmeasured row`() {
                let attestation = Institute.Receipt.Capture.Test.capture()
                let fields = Set(attestation.base.unmeasured.map(\.field))
                #expect(fields.contains("run.conclusion"))
                #expect(fields.contains("jobs[2].conclusion"))
                #expect(attestation.stage == .preterminal)
                #expect(attestation.baseReceiptDigest == nil)
                #expect(attestation.verdict == .preterminal)
            }

            @Test func `gating membership is read from the leading token of a flattened job name`() {
                let attestation = Institute.Receipt.Capture.Test.capture()
                let mandatory = attestation.base.jobs.filter(\.mandatory).map(\.name)
                #expect(mandatory == ["plan", "macos-release build+test"])
                #expect(attestation.base.jobs.map(\.id) == [1, 2, 3])
            }

            @Test func `a skipped advisory job is neither mandatory nor selected`() throws {
                let attestation = Institute.Receipt.Capture.Test.capture()
                let advisory = try #require(attestation.base.jobs.first { $0.id == 3 })
                #expect(!advisory.mandatory)
                #expect(!advisory.selected)
                #expect(advisory.runnerLabels == ["ubuntu-latest"])
            }

            @Test func `a subject sha that is not a full sha is refused`() {
                #expect(throws: Institute.Receipt.Capture.Error.subjectShaNotFull("abc123")) {
                    try Institute.Receipt.Capture.attestation(
                        runJSON: [], jobsJSON: [], plannedGating: [],
                        subjectRepository: "o/n", subjectSha: "abc123",
                        subjectVisibility: "public")
                }
            }
        }

        @Suite
        struct `Edge Case` {
            /// The mandatory P20 control.
            @Test func `the empty chain is refused now and was accepted historically`() {
                let empty = Institute.Receipt.Capture.Test.run(referencedWorkflows: [])

                let historical = Institute.Receipt.Capture.Test.capture(
                    run: empty, emptyChain: .historicallyAccepted)
                #expect(
                    historical.verdict == .preterminal,
                    "the historical variant falsely accepts the empty chain")

                let shipped = Institute.Receipt.Capture.Test.capture(run: empty)
                #expect(shipped.verdict == .unmeasured)
                #expect(
                    Set(shipped.base.unmeasured.map(\.field)).contains("referencedWorkflows"))
            }

            @Test func `a jobs document is read in both the paginated and the bare shape`() throws {
                let rows = try JSONSerialization.data(withJSONObject: Institute.Receipt.Capture.Test.jobs)
                let wrapped = try JSONSerialization.data(
                    withJSONObject: ["jobs": Institute.Receipt.Capture.Test.jobs])
                let runJSON = try JSONSerialization.data(
                    withJSONObject: Institute.Receipt.Capture.Test.run())
                func capture(_ jobs: Data) throws -> Institute.Receipt.Attestation {
                    try Institute.Receipt.Capture.attestation(
                        runJSON: [UInt8](runJSON).map(Byte.init),
                        jobsJSON: [UInt8](jobs).map(Byte.init),
                        plannedGating: Institute.Receipt.Capture.Test.gating,
                        subjectRepository: "swift-foundations/swift-copy-on-write",
                        subjectSha: Institute.Receipt.Capture.Test.subjectSha,
                        subjectVisibility: "public")
                }
                #expect(try capture(rows).base.jobs.count == 3)
                #expect(try capture(wrapped).base.jobs.count == 3)
            }

            @Test func `an absent run field becomes a typed loss rather than a default`() {
                let attestation = Institute.Receipt.Capture.Test.capture(run: [:])
                let fields = Set(attestation.base.unmeasured.map(\.field))
                for field in [
                    "run.id", "run.attempt", "run.headSha", "run.event", "run.repository",
                    "run.workflowPath", "run.actor", "run.headRepository",
                ] {
                    #expect(fields.contains(field))
                }
                #expect(attestation.base.run.id == nil)
            }
        }
    }
}
