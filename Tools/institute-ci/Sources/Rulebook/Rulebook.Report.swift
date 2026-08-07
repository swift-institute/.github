extension Rulebook {
    /// One audit's whole result, and the lines it prints.
    ///
    /// Rendering lives on the value rather than at the command face for
    /// the same reason the exit code does: this text is what a person
    /// reads when a sync aborts, and a second front end that formatted it
    /// slightly differently would make two runs of the same gate look
    /// like two gates.
    public struct Report: Sendable {
        public let results: [Check: [Finding]]
        public let documentCount: Int
        public let definedCount: Int
        public let baseline: Baseline

        public init(
            results: [Check: [Finding]], documentCount: Int, definedCount: Int, baseline: Baseline
        ) {
            self.results = results
            self.documentCount = documentCount
            self.definedCount = definedCount
            self.baseline = baseline
        }

        /// The checks that ran, in declaration order.
        public var checks: [Check] { Check.allCases.filter { results[$0] != nil } }

        /// Findings the baseline does not already carry — the ones that
        /// count.
        public func fresh(_ check: Check) -> [Finding] {
            (results[check] ?? []).filter { !baseline.covers($0) }
        }

        public var freshCount: Int { checks.reduce(0) { $0 + fresh($1).count } }

        public var baselinedCount: Int {
            checks.reduce(0) { $0 + (results[$1]?.count ?? 0) - fresh($1).count }
        }

        /// Every finding is known.
        public var isClean: Bool { freshCount == 0 }

        /// The report, as printed.
        public func lines(enforcing: Bool) -> [String] {
            var lines: [String] = []
            for check in checks {
                let all = results[check] ?? []
                let fresh = fresh(check)
                let baselined = all.count - fresh.count
                let status = fresh.isEmpty ? "OK" : "\(fresh.count) finding(s)"
                lines.append(
                    "check-canon[\(check.rawValue)]: \(status)"
                        + (baselined > 0 ? " (\(baselined) baselined)" : ""))
                lines.append(contentsOf: fresh.map { "  \($0.message)" })
            }
            lines.append(
                "check-canon: \(freshCount) new finding(s), \(baselinedCount) baselined, "
                    + "\(documentCount) files, \(definedCount) defined ids"
                    + (enforcing ? "" : " [report-only]"))
            return lines
        }

        /// Baseline lines for every current finding — what
        /// `--emit-baseline` writes.
        public var baselineEntries: [String] {
            checks.flatMap { check in (results[check] ?? []).map(\.baselineEntry) }
        }
    }
}
