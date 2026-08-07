import CI_Contract
import CI_Workflow

extension CI.Inventory {
    /// The universal reusable workflow (`.github/workflows/swift-ci.yml`),
    /// inventoried.
    ///
    /// Everything here is **derived** from the shipped document. Nothing
    /// is asserted: an inventory that carried its own opinion of what
    /// the jobs ought to be would agree with itself forever. The
    /// assertions live in the test suite, over this value.
    public struct Universal: Sendable, Equatable {
        public let jobs: [Job]
        public let plan: Plan
        public let aggregate: Aggregate
        public let cacheSteps: [CacheStep]

        /// GitHub Actions' own enum for `needs.<job>.result`. Recorded
        /// because the aggregate's shell compares against these four
        /// strings and a fifth would silently fall through.
        public static let possibleJobConclusions = [
            "success", "failure", "cancelled", "skipped",
        ]

        static let nestedTestMarker = "Tests/Package.swift"

        public var jobCount: Int { jobs.count }

        public func job(_ id: String) -> Job? { jobs.first { $0.id == id } }

        /// Derives the inventory from one workflow document.
        public init(_ document: CI.Workflow.Document) throws(Error) {
            let jobs = document.jobs
            guard !jobs.isEmpty else { throw .noJobs }
            guard let ciOk = jobs.first(where: { $0.name == "ci-ok" }) else {
                throw .missingJob("ci-ok")
            }
            guard let planJob = jobs.first(where: { $0.name == "plan" }) else {
                throw .missingJob("plan")
            }
            let advisorySummary = jobs.first { $0.name == "advisory-summary" }

            let aggregate = Aggregate(
                ciOkNeeds: Self.needs(of: ciOk),
                advisorySummaryNeeds: advisorySummary.map(Self.needs) ?? [],
                innerMatrixJobs: jobs.filter { Self.matrixAxes(of: $0) != nil }.map(\.name))
            self.aggregate = aggregate

            let gating = Set(aggregate.gatingJobs)
            let advisory = Set(aggregate.advisoryJobs)
            var waves: [String: Int] = [:]
            let needsByJob = Dictionary(
                uniqueKeysWithValues: jobs.map { ($0.name, Self.needs(of: $0)) })

            self.jobs = jobs.map { job in
                let condition = job.body["if"]?.text
                return Job(
                    id: job.name,
                    displayName: job.body["name"]?.text,
                    runner: job.runsOn ?? job.body["uses"],
                    needs: needsByJob[job.name] ?? [],
                    condition: condition,
                    continueOnError: job.continueOnError?.boolean ?? false,
                    privateGuarded: (condition ?? "")
                        .contains("github.event.repository.private"),
                    matrixAxes: Self.matrixAxes(of: job),
                    permissions: job.body["permissions"],
                    nestedTestExecution: job.steps.contains {
                        ($0["run"]?.text ?? "").contains(Self.nestedTestMarker)
                    },
                    stepNames: job.steps.map { $0["name"]?.text },
                    posture: Self.posture(
                        of: job.name, gating: gating, advisory: advisory),
                    wave: Self.wave(of: job.name, needs: needsByJob, cache: &waves))
            }

            self.plan = Plan(
                delegatesToInstituteCI: planJob.steps.contains { step in
                    step["name"]?.text == Plan.classifyStep
                        && (step["run"]?.text ?? "").contains("institute-ci plan")
                })

            self.cacheSteps = jobs.flatMap { job in
                job.steps
                    .filter { ($0["uses"]?.text ?? "").hasPrefix("actions/cache@") }
                    .map { step in
                        CacheStep(
                            job: job.name,
                            step: step["name"]?.text,
                            path: step["with"]?["path"],
                            key: step["with"]?["key"])
                    }
            }
        }

        public var node: CI.Workflow.YAML.Node {
            .mapping(
                .init([
                    (
                        .text("jobs"),
                        .mapping(.init(jobs.map { (CI.Workflow.YAML.Node.text($0.id), $0.node) }))
                    ),
                    (.text("job_count"), .integer(jobCount)),
                    (
                        .text("gating_jobs"),
                        .sequence(aggregate.gatingJobs.map(CI.Workflow.YAML.Node.text))
                    ),
                    (
                        .text("advisory_jobs"),
                        .sequence(aggregate.advisoryJobs.map(CI.Workflow.YAML.Node.text))
                    ),
                    (.text("plan"), plan.node),
                    (.text("aggregate"), aggregate.node),
                    (.text("cache_steps"), .sequence(cacheSteps.map(\.node))),
                    (
                        .text("possible_job_conclusions"),
                        .sequence(Self.possibleJobConclusions.map(CI.Workflow.YAML.Node.text))
                    ),
                ]))
        }

        /// A job's `needs`, normalised: Actions allows a bare scalar.
        static func needs(of job: CI.Workflow.Job) -> [String] {
            guard let node = job.body["needs"] else { return [] }
            if let single = node.text { return [single] }
            return node.sequence?.compactMap(\.text) ?? []
        }

        static func matrixAxes(of job: CI.Workflow.Job) -> CI.Workflow.YAML.Node? {
            job.body["strategy"]?["matrix"]
        }

        static func posture(
            of id: String, gating: Set<String>, advisory: Set<String>
        ) -> Posture {
            switch id {
            case "plan": .plan
            case "ci-ok", "advisory-summary": .aggregate
            case let id where gating.contains(id): .gating
            case let id where advisory.contains(id): .advisory
            default: .eventGated
            }
        }

        /// The DAG wave, memoised. A `needs` entry naming a job that is
        /// not declared contributes nothing — Actions would refuse the
        /// workflow outright, and inventing a wave for it here would
        /// describe a run that cannot happen.
        static func wave(
            of id: String, needs: [String: [String]], cache: inout [String: Int]
        ) -> Int {
            if let known = cache[id] { return known }
            let declared = (needs[id] ?? []).filter { needs[$0] != nil }
            guard !declared.isEmpty else {
                cache[id] = 0
                return 0
            }
            // Seeded before recursing: a cyclic `needs` graph is not a
            // legal workflow, and this bounds the recursion rather than
            // trusting that.
            cache[id] = 0
            let wave = 1 + declared.map { wave(of: $0, needs: needs, cache: &cache) }.max()!
            cache[id] = wave
            return wave
        }
    }
}
