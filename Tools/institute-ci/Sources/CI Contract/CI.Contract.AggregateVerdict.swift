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
        public init(
            planResult: String,
            results: [String: String],
            gating: [String],
            subjectRepository: String,
            subjectSha: String,
            tier: String,
            requireFullTier: Bool
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
            var built: [String] = []
            let gatingSet = Set(gating)
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
            if built.isEmpty {
                findings.append(.nothingBuilt)
            }
            self.findings = findings
            self.built = built
            self.pass = findings.isEmpty
        }
    }
}
