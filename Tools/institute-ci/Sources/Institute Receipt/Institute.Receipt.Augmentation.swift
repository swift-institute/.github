extension Institute.Receipt {
    /// Turns a preterminal record into the terminal one, after the
    /// producing run has completed.
    ///
    /// The collector runs outside the run it attests, which is the only
    /// vantage point from which that run's conclusion exists. What it
    /// may change is deliberately tiny: the run's conclusion, each job's
    /// conclusion, the stage, the binding digest, and the verdict. Every
    /// other fact is carried over from the preterminal record unchanged
    /// — and because both records are the same typed value re-encoded
    /// through one codec, "unchanged" is a property of the type rather
    /// than something a reviewer has to diff for.
    ///
    /// Before it changes anything it requires immutable-identity
    /// equality between the two reads. A collector that augmented one
    /// run's record with another run's conclusions would produce a
    /// perfectly well-formed receipt attesting nothing, and no later
    /// check could detect it: the digest would verify.
    public enum Augmentation {}
}

extension Institute.Receipt.Augmentation {
    /// A refusal — the collector declines to mint a terminal record.
    ///
    /// Every case is a reason the terminal claim would be unsupported,
    /// not a reason the run failed. A failed run yields a `FAILED`
    /// verdict, which is a receipt; these yield no receipt at all.
    public enum Refusal: Swift.Error, Sendable, Equatable {
        /// The fetched base record does not carry the preterminal
        /// null-digest shape.
        case baseNotPreterminal
        case runNotCompleted(status: String)
        case attemptMismatch(requested: Int, live: Int?)
        case identityMismatch(field: String, base: String, live: String)
        /// The run reports `completed` and exposes no conclusion.
        case missingTerminalConclusion
    }

    /// What the collector concluded, and about which jobs.
    public struct Outcome: Sendable, Equatable {
        public let attestation: Institute.Receipt.Attestation
        /// Mandatory selected jobs that did not conclude success — the
        /// evidence behind a `FAILED` verdict, reported rather than
        /// summarised so the operator sees which gate fell.
        public let mandatoryFailures: [Institute.Receipt.Job]

        public init(
            attestation: Institute.Receipt.Attestation,
            mandatoryFailures: [Institute.Receipt.Job]
        ) {
            self.attestation = attestation
            self.mandatoryFailures = mandatoryFailures
        }
    }

    /// The terminal record for a completed run.
    ///
    /// - Parameters:
    ///   - base: the preterminal attestation, as read from the artifact.
    ///   - baseReceiptDigest: the digest of the bytes that artifact
    ///     actually carried — never a re-encoding of `base`, so a record
    ///     that was altered in transit cannot bind to itself.
    ///   - run: the completed run, read after the fact.
    ///   - status: the run's `status` field, which must be `completed`.
    ///   - attempt: the attempt the collector was asked to augment.
    ///   - conclusions: live conclusion by job id, from the complete
    ///     paginated jobs collection.
    public static func outcome(
        base: Institute.Receipt.Attestation,
        baseReceiptDigest: String,
        run: Institute.Receipt.Run,
        status: String,
        attempt: Int,
        conclusions: [Int: Institute.Receipt.Conclusion?]
    ) throws(Refusal) -> Outcome {
        guard base.stage == .preterminal, base.baseReceiptDigest == nil else {
            throw .baseNotPreterminal
        }
        guard status == "completed" else { throw .runNotCompleted(status: status) }
        guard run.attempt == attempt else {
            throw .attemptMismatch(requested: attempt, live: run.attempt)
        }
        for (field, recorded, live) in [
            ("run.id", base.base.run.id.map(String.init), run.id.map(String.init)),
            ("run.attempt", base.base.run.attempt.map(String.init), run.attempt.map(String.init)),
            ("run.headSha", base.base.run.headSha, run.headSha),
            ("run.repository", base.base.run.repository, run.repository),
            ("run.workflowPath", base.base.run.workflowPath, run.workflowPath),
        ] where recorded != live {
            throw .identityMismatch(
                field: field, base: recorded ?? "null", live: live ?? "null")
        }
        guard let conclusion = run.conclusion else { throw .missingTerminalConclusion }

        var jobs: [Institute.Receipt.Job] = []
        var mandatoryFailures: [Institute.Receipt.Job] = []
        for job in base.base.jobs {
            // A job present in the live collection with a null
            // conclusion keeps that null; only a job absent from it
            // keeps what the base record recorded.
            let live: Institute.Receipt.Conclusion?
            if let id = job.id, let entry = conclusions[id] {
                live = entry
            } else {
                live = job.conclusion
            }
            let augmented = Institute.Receipt.Job(
                id: job.id, name: job.name, conclusion: live,
                selected: job.selected, mandatory: job.mandatory,
                runnerLabels: job.runnerLabels)
            jobs.append(augmented)
            if job.mandatory && live != .success { mandatoryFailures.append(augmented) }
        }

        // Every conclusion the record admitted it could not measure has
        // now been measured; the rows that named those losses are
        // retired, and no other row is.
        let unmeasured = base.base.unmeasured.filter {
            $0.field != "run.conclusion" && !$0.field.hasSuffix(".conclusion")
        }
        let verdict: Institute.Receipt.Verdict
        if base.verdict == .unmeasured || base.base.referencedWorkflows.isEmpty {
            verdict = .unmeasured
        } else if conclusion == .success && mandatoryFailures.isEmpty {
            verdict = .met
        } else {
            verdict = .failed
        }
        let terminal = Institute.Receipt.Attestation(
            base: .init(
                run: .init(
                    id: base.base.run.id, attempt: base.base.run.attempt,
                    headSha: base.base.run.headSha, event: base.base.run.event,
                    conclusion: conclusion,
                    repository: base.base.run.repository,
                    workflowPath: base.base.run.workflowPath,
                    actor: base.base.run.actor,
                    headRepository: base.base.run.headRepository,
                    headBranch: base.base.run.headBranch),
                subjectRepository: base.base.subjectRepository,
                subjectSha: base.base.subjectSha,
                subjectVisibility: base.base.subjectVisibility,
                referencedWorkflows: base.base.referencedWorkflows,
                jobs: jobs,
                jobsTotalCount: base.base.jobsTotalCount,
                unmeasured: unmeasured),
            stage: .terminal,
            baseReceiptDigest: baseReceiptDigest,
            verdict: verdict)
        return .init(attestation: terminal, mandatoryFailures: mandatoryFailures)
    }
}
