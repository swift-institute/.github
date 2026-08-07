import Institute_Receipt
import Testing

extension Institute.Receipt.Augmentation {
    @Suite
    struct Test {
        @Suite
        struct Integration {}

        static let headSha = String(repeating: "a", count: 40)
        static let digest = String(repeating: "d", count: 64)

        static func base(
            referenced: [Institute.Receipt.ReferencedWorkflow]? = nil,
            verdict: Institute.Receipt.Verdict = .preterminal
        ) -> Institute.Receipt.Attestation {
            .init(
                base: .init(
                    run: .init(
                        id: 31_000_000_001, attempt: 1, headSha: headSha,
                        event: "push", conclusion: nil,
                        repository: "swift-institute/.github",
                        workflowPath: ".github/workflows/swift-ci.yml"),
                    subjectRepository: "swift-foundations/swift-copy-on-write",
                    subjectSha: String(repeating: "b", count: 40),
                    subjectVisibility: "public",
                    referencedWorkflows: referenced ?? [
                        .init(path: "swift-ci.yml", ref: "refs/heads/main", sha: headSha)
                    ],
                    jobs: [
                        .init(id: 1, name: "plan", conclusion: .success, selected: true,
                              mandatory: true),
                        .init(id: 2, name: "macos-release", conclusion: nil, selected: true,
                              mandatory: true),
                        .init(id: 3, name: "lint-yaml", conclusion: .skipped, selected: false,
                              mandatory: false),
                    ],
                    jobsTotalCount: nil,
                    unmeasured: [
                        .init(field: "jobs[2].conclusion", reason: "not terminal at capture"),
                        .init(field: "run.conclusion", reason: "not terminal at capture"),
                        .init(field: "linter", reason: "not exposed at capture"),
                    ]),
                stage: .preterminal,
                baseReceiptDigest: nil,
                verdict: verdict)
        }

        static func live(
            conclusion: Institute.Receipt.Conclusion? = .success,
            attempt: Int? = 1,
            headSha: String? = nil
        ) -> Institute.Receipt.Run {
            .init(
                id: 31_000_000_001, attempt: attempt, headSha: headSha ?? Self.headSha,
                event: "push", conclusion: conclusion,
                repository: "swift-institute/.github",
                workflowPath: ".github/workflows/swift-ci.yml")
        }

        static func outcome(
            base: Institute.Receipt.Attestation? = nil,
            run: Institute.Receipt.Run? = nil,
            status: String = "completed",
            attempt: Int = 1,
            conclusions: [Int: Institute.Receipt.Conclusion?] = [1: .success, 2: .success, 3: .skipped]
        ) throws -> Institute.Receipt.Augmentation.Outcome {
            try Institute.Receipt.Augmentation.outcome(
                base: base ?? Self.base(),
                baseReceiptDigest: digest,
                run: run ?? live(),
                status: status,
                attempt: attempt,
                conclusions: conclusions)
        }

        @Suite
        struct Unit {
            @Test func `a clean completed run yields a bound terminal MET receipt`() throws {
                let outcome = try Institute.Receipt.Augmentation.Test.outcome()
                #expect(outcome.attestation.stage == .terminal)
                #expect(outcome.attestation.verdict == .met)
                #expect(
                    outcome.attestation.baseReceiptDigest
                        == Institute.Receipt.Augmentation.Test.digest)
                #expect(outcome.mandatoryFailures.isEmpty)
                #expect(outcome.attestation.terminal.validate() == [])
            }

            @Test func `the rows naming measured losses retire and the others do not`() throws {
                let outcome = try Institute.Receipt.Augmentation.Test.outcome()
                #expect(outcome.attestation.base.unmeasured.map(\.field) == ["linter"])
            }

            @Test func `only the terminal facts differ from the base record`() throws {
                let base = Institute.Receipt.Augmentation.Test.base()
                let terminal = try Institute.Receipt.Augmentation.Test.outcome().attestation
                #expect(terminal.base.subjectSha == base.base.subjectSha)
                #expect(terminal.base.referencedWorkflows == base.base.referencedWorkflows)
                #expect(terminal.base.run.id == base.base.run.id)
                #expect(terminal.base.jobs.map(\.name) == base.base.jobs.map(\.name))
                #expect(terminal.base.jobs.map(\.mandatory) == base.base.jobs.map(\.mandatory))
                #expect(terminal.base.run.conclusion == .success)
            }

            @Test func `a non success mandatory job makes the verdict FAILED and is named`() throws {
                let outcome = try Institute.Receipt.Augmentation.Test.outcome(
                    conclusions: [1: .success, 2: .cancelled, 3: .skipped])
                #expect(outcome.attestation.verdict == .failed)
                #expect(outcome.mandatoryFailures.map(\.name) == ["macos-release"])
            }

            @Test func `a failed run is FAILED even with every mandatory job green`() throws {
                let outcome = try Institute.Receipt.Augmentation.Test.outcome(
                    run: Institute.Receipt.Augmentation.Test.live(conclusion: .failure))
                #expect(outcome.attestation.verdict == .failed)
            }
        }

        @Suite
        struct `Edge Case` {
            @Test func `an unmeasured base stays unmeasured however green the run`() throws {
                let outcome = try Institute.Receipt.Augmentation.Test.outcome(
                    base: Institute.Receipt.Augmentation.Test.base(
                        referenced: [], verdict: .unmeasured))
                #expect(outcome.attestation.verdict == .unmeasured)
            }

            @Test func `a run that is not completed is refused`() {
                #expect(throws: Institute.Receipt.Augmentation.Refusal.runNotCompleted(
                    status: "in_progress")
                ) {
                    try Institute.Receipt.Augmentation.Test.outcome(status: "in_progress")
                }
            }

            @Test func `the wrong attempt is refused`() {
                #expect(throws: Institute.Receipt.Augmentation.Refusal.attemptMismatch(
                    requested: 2, live: 1)
                ) {
                    try Institute.Receipt.Augmentation.Test.outcome(attempt: 2)
                }
            }

            /// The refusal that matters most: augmenting one run's record with
            /// another run's conclusions produces a well-formed receipt whose
            /// digest verifies and which attests nothing.
            @Test func `an immutable identity mismatch is refused`() {
                let other = String(repeating: "c", count: 40)
                #expect(throws: Institute.Receipt.Augmentation.Refusal.identityMismatch(
                    field: "run.headSha",
                    base: Institute.Receipt.Augmentation.Test.headSha,
                    live: other)
                ) {
                    try Institute.Receipt.Augmentation.Test.outcome(
                        run: Institute.Receipt.Augmentation.Test.live(headSha: other))
                }
            }

            @Test func `a base that is already terminal is refused`() {
                let bound = Institute.Receipt.Attestation(
                    base: Institute.Receipt.Augmentation.Test.base().base,
                    stage: .terminal,
                    baseReceiptDigest: Institute.Receipt.Augmentation.Test.digest,
                    verdict: .met)
                #expect(throws: Institute.Receipt.Augmentation.Refusal.baseNotPreterminal) {
                    try Institute.Receipt.Augmentation.Test.outcome(base: bound)
                }
            }

            @Test func `a completed run exposing no conclusion is refused`() {
                #expect(throws: Institute.Receipt.Augmentation.Refusal.missingTerminalConclusion) {
                    try Institute.Receipt.Augmentation.Test.outcome(
                        run: Institute.Receipt.Augmentation.Test.live(conclusion: nil))
                }
            }

            @Test func `a job present live with a null conclusion keeps the null`() throws {
                let outcome = try Institute.Receipt.Augmentation.Test.outcome(
                    conclusions: [1: .success, 2: Institute.Receipt.Conclusion?.none, 3: .skipped])
                let macos = outcome.attestation.base.jobs.first { $0.id == 2 }
                #expect(macos?.conclusion == nil)
                #expect(outcome.attestation.verdict == .failed)
            }
        }
    }
}
