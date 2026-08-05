extension Institute.Receipt {
    /// The terminal (post-run, collector-augmented) receipt: the
    /// preterminal record plus the base-receipt binding digest. Terminal
    /// validation is `Terminal.validate()`; refusal semantics live in
    /// `Institute.Receipt.FailureClass`.
    public struct Terminal: Sendable, Equatable {
        public let base: Preterminal
        /// SHA-256 of the preterminal record this terminal record
        /// augments; a terminal record without one is not terminal.
        public let baseReceiptDigest: String?

        public init(base: Preterminal, baseReceiptDigest: String?) {
            self.base = base
            self.baseReceiptDigest = baseReceiptDigest
        }

        /// Terminal readiness (K-21 semantics, R35 §8.13 as corrected):
        /// empty identity families and zero mandatory jobs refuse unless
        /// an exact typed inapplicability (unmeasured-with-cause) applies.
        public func validate(requireCompletedRun: Bool = true) -> [FailureClass] {
            var findings: [FailureClass] = []
            if baseReceiptDigest == nil {
                findings.append(.stageNotTerminal(field: "baseReceiptDigest"))
            } else if let digest = baseReceiptDigest, !Self.isHex64(digest) {
                findings.append(.shortSha(field: "baseReceiptDigest", value: digest))
            }
            let typed = Set(base.unmeasured.map(\.field))
            if requireCompletedRun && base.run.conclusion == nil {
                findings.append(.nullTerminalField(field: "run.conclusion"))
            } else if base.run.conclusion == nil && !typed.contains("run.conclusion") {
                findings.append(.nullTerminalField(field: "run.conclusion"))
            }
            if !Self.isFullSha(base.run.headSha) {
                findings.append(.shortSha(field: "run.headSha", value: base.run.headSha))
            }
            if base.subjectRepository.isEmpty || base.subjectSha.isEmpty {
                findings.append(.emptySubject)
            } else if !Self.isFullSha(base.subjectSha) {
                findings.append(.shortSha(field: "subjectSha", value: base.subjectSha))
            }
            if base.referencedWorkflows.isEmpty && !typed.contains("referencedWorkflows") {
                findings.append(.emptyIdentityFamily(field: "referencedWorkflows"))
            }
            for hop in base.referencedWorkflows where !Self.isFullSha(hop.sha) {
                findings.append(.shortSha(field: "referencedWorkflows[\(hop.path)]", value: hop.sha))
            }
            for job in base.jobs where job.mandatory {
                if job.conclusion == nil && !typed.contains("jobs[\(job.id)].conclusion") {
                    findings.append(.nullTerminalField(field: "jobs[\(job.id)]"))
                }
                if let conclusion = job.conclusion,
                   conclusion == "skipped" || conclusion == "cancelled" {
                    findings.append(.mandatoryJobNotSuccess(job: job.id, conclusion: conclusion))
                }
            }
            // R35/K-21 correction: a terminal receipt over a run with no
            // mandatory jobs attests nothing. The historical validator
            // accepted this shape (the f22 defect); this owner refuses it
            // unless an exact typed inapplicability names the field.
            if !base.jobs.contains(where: \.mandatory) && !typed.contains("jobs.mandatory") {
                findings.append(.zeroMandatoryJobs)
            }
            if let total = base.jobsTotalCount, total != base.jobs.count {
                findings.append(.jobsPaginationIncomplete(total: total, present: base.jobs.count))
            }
            return findings
        }

        static func isFullSha(_ value: String) -> Bool {
            value.count == 40 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }

        static func isHex64(_ value: String) -> Bool {
            value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }
    }
}
