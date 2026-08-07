import CI_Contract

extension CI.Workflow {
    /// One entry of a workflow's `jobs:` mapping.
    public struct Job: Sendable, Equatable {
        public let name: String
        public let body: YAML.Mapping

        public init(name: String, body: YAML.Mapping) {
            self.name = name
            self.body = body
        }

        /// The reusable workflow this job delegates to, when it is a
        /// caller job. `nil` — including for a blank `uses:` — means the
        /// job runs its own steps.
        public var uses: String? {
            guard let text = body["uses"]?.text else { return nil }
            let trimmed = text.trimmed(of: [" ", "\t"])
            return trimmed.isEmpty ? nil : trimmed
        }

        /// True when the job delegates to a reusable workflow. The
        /// distinction matters to several rules because Actions applies
        /// different key sets to caller jobs and regular jobs.
        public var isCaller: Bool { uses != nil }

        public var runsOn: YAML.Node? { body["runs-on"] }

        /// The job's steps, when it declares any.
        public var steps: [YAML.Mapping] {
            body["steps"]?.sequence?.compactMap(\.mapping) ?? []
        }

        /// Job-level `continue-on-error`, unresolved.
        ///
        /// Returned as a node rather than a `Bool` on purpose: the key
        /// legitimately holds a boolean, the *string* `"true"`, or an
        /// unevaluated `${{ }}` expression, and a rule must be able to
        /// tell those apart.
        public var continueOnError: YAML.Node? { body["continue-on-error"] }
    }
}

extension String {
    fileprivate func trimmed(of set: Set<Character>) -> String {
        var result = Substring(self)
        while let first = result.first, set.contains(first) { result = result.dropFirst() }
        while let last = result.last, set.contains(last) { result = result.dropLast() }
        return String(result)
    }
}
