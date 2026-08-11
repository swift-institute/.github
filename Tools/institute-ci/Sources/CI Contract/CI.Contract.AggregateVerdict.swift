extension CI.Contract {
    /// The ci-ok aggregate: attests that the SELECTED tier passed and the
    /// selected tier built the package. Semantics mirror the swift-ci.yml
    /// "Aggregate required-job results" step (F4; #368).
    public struct AggregateVerdict: Sendable, Equatable {
        public enum Finding: Sendable, Equatable {
            case planDidNotSucceed(result: String)
            case emptyGating
            case emptySubject
            case fullTierRequired(got: String)
            case selectedLegNotSuccessful(job: String, result: String)
            case unselectedLegRan(job: String, result: String)
            case nothingBuilt
            /// A leg the plan descheduled with a reason nevertheless ran —
            /// the descheduling record and the execution graph disagree.
            case descheduledLegRan(job: String, result: String)
            /// The plan's descheduled record names a gating leg. Advisory-
            /// class descheduling must never be able to account for a
            /// gating obligation (ruled 2026-08-10, .github#488).
            case descheduledGatingLeg(job: String)
        }

        public let pass: Bool
        public let findings: [Finding]
        public let built: [String]

        /// - Parameters:
        ///   - planResult: the plan job's result string.
        ///   - results: every participating job id (ci-ok's needs minus
        ///     plan) to its result string, iterated in sorted order.
        ///   - gating: the plan's gating leg ids.
        ///   - subject: the plan-resolved subject; nil/empty refuses.
        ///   - tier: the planned tier string.
        ///   - requireFullTier: true on the main integration ref.
        ///   - descheduled: leg ids the plan removed with a typed reason
        ///     (`leg=reason` records upstream; ids here). Audited as the
        ///     third state — accounted-for-with-reason — distinct from
        ///     scheduled and absent: each must have skipped, and none may
        ///     be gating.
        public init(
            planResult: String,
            results: [String: String],
            gating: [String],
            subjectRepository: String,
            subjectSha: String,
            tier: String,
            requireFullTier: Bool,
            packageContentChanged: Bool = true,
            descheduled: [String] = []
        ) {
            var findings: [Finding] = []
            if planResult != "success" {
                findings.append(.planDidNotSucceed(result: planResult))
            }
            if gating.isEmpty {
                findings.append(.emptyGating)
            }
            if subjectRepository.isEmpty || subjectSha.isEmpty {
                findings.append(.emptySubject)
            }
            if requireFullTier && tier != "full" {
                findings.append(.fullTierRequired(got: tier))
            }
            let gatingSet = Set(gating)
            let descheduledSet = Set(descheduled)
            for job in descheduled.sorted() {
                if gatingSet.contains(job) || CI.Contract.Leg(job).gating {
                    findings.append(.descheduledGatingLeg(job: job))
                }
                if let result = results[job], result != "skipped" {
                    findings.append(.descheduledLegRan(job: job, result: result))
                }
            }
            var built: [String] = []
            for job in results.keys.sorted() where job != "plan" {
                let result = results[job]!
                let expected = gatingSet.contains(job) ? "success" : "skipped"
                if result != expected {
                    if expected == "success" {
                        findings.append(.selectedLegNotSuccessful(job: job, result: result))
                    } else {
                        findings.append(.unselectedLegRan(job: job, result: result))
                    }
                }
                if CI.Contract.Leg(job).buildLeg && result == "success" {
                    built.append(job)
                }
            }
            if packageContentChanged && built.isEmpty {
                findings.append(.nothingBuilt)
            }
            self.findings = findings
            self.built = built
            self.pass = findings.isEmpty
        }
    }
}
