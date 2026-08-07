import CI_Contract
import CI_Workflow

extension CI.Inventory {
    /// Why an inventory could not be derived.
    ///
    /// Every case names a construct the universal workflow is required
    /// to have. An inventory is a description of the shipped verdict; if
    /// the verdict's own scaffolding is missing, there is nothing to
    /// describe, and reporting an empty inventory would read as "the CI
    /// has no jobs" rather than "this file is not the universal".
    public enum Error: Swift.Error, Equatable {
        /// The workflow document could not be read as YAML.
        case unreadableWorkflow(message: String)
        /// The document has no `jobs:` mapping.
        case noJobs
        /// A job the aggregate depends on is absent.
        case missingJob(String)

        public var message: String {
            switch self {
            case .unreadableWorkflow(let message):
                "the universal workflow could not be read: \(message)"
            case .noJobs:
                "the universal workflow declares no jobs"
            case .missingJob(let job):
                "the universal workflow declares no '\(job)' job"
            }
        }
    }
}
