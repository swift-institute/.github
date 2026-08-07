import Institute_Receipt
import Testing

@Suite
struct InstituteReceiptTests {
    static let sha = String(repeating: "a", count: 40)
    static let digest = String(repeating: "b", count: 64)

    func preterminal(
        conclusion: Institute.Receipt.Conclusion? = .success,
        referenced: [Institute.Receipt.ReferencedWorkflow]? = nil,
        jobs: [Institute.Receipt.Job]? = nil,
        totalCount: Int? = nil,
        unmeasured: [Institute.Receipt.Unmeasured] = []
    ) -> Institute.Receipt.Preterminal {
        let defaultJobs = jobs ?? [
            .init(id: 1, name: "ci-ok", conclusion: "success", selected: true, mandatory: true),
            .init(id: 2, name: "linux-release", conclusion: "success", selected: true, mandatory: true),
        ]
        return .init(
            run: .init(id: 31010155651, attempt: 1, headSha: Self.sha,
                       event: "workflow_dispatch", conclusion: conclusion),
            subjectRepository: "swift-foundations/swift-copy-on-write",
            subjectSha: Self.sha,
            referencedWorkflows: referenced ?? [
                .init(path: ".github/workflows/swift-ci.yml", ref: "main", sha: Self.sha)
            ],
            jobs: defaultJobs, jobsTotalCount: totalCount,
            unmeasured: unmeasured)
    }

    @Test
    func conformingTerminalReceiptValidates() {
        let terminal = Institute.Receipt.Terminal(
            base: preterminal(totalCount: 2), baseReceiptDigest: Self.digest)
        #expect(terminal.validate() == [])
    }

    @Test
    func terminalWithoutBaseDigestRefuses() {
        let terminal = Institute.Receipt.Terminal(
            base: preterminal(), baseReceiptDigest: nil)
        #expect(terminal.validate().contains(.stageNotTerminal(field: "baseReceiptDigest")))
    }

    @Test
    func nullConclusionOnRequiredCompletedRunRefuses() {
        let terminal = Institute.Receipt.Terminal(
            base: preterminal(conclusion: nil), baseReceiptDigest: Self.digest)
        #expect(terminal.validate().contains(.nullTerminalField(field: "run.conclusion")))
    }

    @Test
    func emptyReferencedWorkflowsRefusesUnlessTyped() {
        let bare = Institute.Receipt.Terminal(
            base: preterminal(referenced: []), baseReceiptDigest: Self.digest)
        #expect(bare.validate().contains(.emptyIdentityFamily(field: "referencedWorkflows")))
        let typed = Institute.Receipt.Terminal(
            base: preterminal(
                referenced: [],
                unmeasured: [.init(field: "referencedWorkflows",
                                   reason: "empty referenced_workflows collection at capture")]),
            baseReceiptDigest: Self.digest)
        #expect(!typed.validate().contains(.emptyIdentityFamily(field: "referencedWorkflows")))
    }

    @Test
    func skippedOrCancelledMandatoryJobRefuses() {
        for conclusion: Institute.Receipt.Conclusion in [.skipped, .cancelled] {
            let terminal = Institute.Receipt.Terminal(
                base: preterminal(jobs: [
                    .init(id: 1, name: "linux-release", conclusion: conclusion,
                          selected: true, mandatory: true)
                ]),
                baseReceiptDigest: Self.digest)
            #expect(terminal.validate().contains(
                .mandatoryJobNotSuccess(job: "1", conclusion: conclusion)))
        }
    }

    @Test
    func zeroMandatoryJobsRefusesUnlessTyped() {
        let advisoryOnly = [Institute.Receipt.Job(
            id: 3, name: "advisory", conclusion: "success",
            selected: true, mandatory: false)]
        let bare = Institute.Receipt.Terminal(
            base: preterminal(jobs: advisoryOnly), baseReceiptDigest: Self.digest)
        #expect(bare.validate().contains(.zeroMandatoryJobs))
        let typed = Institute.Receipt.Terminal(
            base: preterminal(
                jobs: advisoryOnly,
                unmeasured: [.init(field: "jobs.mandatory",
                                   reason: "typed inapplicability per R35")]),
            baseReceiptDigest: Self.digest)
        #expect(!typed.validate().contains(.zeroMandatoryJobs))
    }

    @Test
    func incompletePaginationRefuses() {
        let terminal = Institute.Receipt.Terminal(
            base: preterminal(totalCount: 50), baseReceiptDigest: Self.digest)
        #expect(terminal.validate().contains(
            .jobsPaginationIncomplete(total: 50, present: 2)))
    }

    @Test
    func shortShaRefuses() {
        let terminal = Institute.Receipt.Terminal(
            base: preterminal(referenced: [
                .init(path: "w.yml", ref: "main", sha: "abc123")
            ]),
            baseReceiptDigest: Self.digest)
        #expect(terminal.validate().contains(
            .shortSha(field: "referencedWorkflows[w.yml]", value: "abc123")))
    }

    @Test
    func emptySubjectRefuses() {
        let base = Institute.Receipt.Preterminal(
            run: .init(id: 1, attempt: 1, headSha: Self.sha, event: "push",
                       conclusion: "success"),
            subjectRepository: "", subjectSha: "",
            referencedWorkflows: [.init(path: "w", ref: "main", sha: Self.sha)],
            jobs: [.init(id: 1, name: "linux-release", conclusion: "success",
                         selected: true, mandatory: true)],
            jobsTotalCount: nil, unmeasured: [])
        let terminal = Institute.Receipt.Terminal(base: base, baseReceiptDigest: Self.digest)
        #expect(terminal.validate().contains(.emptySubject))
    }
}
