import CI_Contract
import CI_Workflow

extension CI.Inventory {
    /// One `actions/cache` step, and what it caches.
    ///
    /// Enumerated because the cache policy carries one standing
    /// prohibition — `.build/` is never cached, so a green run is never
    /// green because of a stale object file. The inventory records the
    /// paths; the assertion over them lives in the test suite, where a
    /// violation reads as a failure rather than as a field.
    public struct CacheStep: Sendable, Equatable {
        public let job: String
        public let step: String?
        public let path: CI.Workflow.YAML.Node?
        public let key: CI.Workflow.YAML.Node?

        public init(
            job: String,
            step: String?,
            path: CI.Workflow.YAML.Node?,
            key: CI.Workflow.YAML.Node?
        ) {
            self.job = job
            self.step = step
            self.path = path
            self.key = key
        }

        public var node: CI.Workflow.YAML.Node {
            .mapping(
                .init([
                    (.text("job"), .text(job)),
                    (.text("step"), step.map(CI.Workflow.YAML.Node.text) ?? .null),
                    (.text("path"), path ?? .null),
                    (.text("key"), key ?? .null),
                ]))
        }
    }
}
