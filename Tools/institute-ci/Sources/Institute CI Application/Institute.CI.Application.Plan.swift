import CI_Contract
import Institute_Receipt

// Nest.Name namespaces (FT1-ratification.json). The Application layer
// orchestrates use cases and owns no predicate; predicates live in
// CI Contract and Institute Receipt. `Institute` is Institute Receipt's
// namespace, extended here.
extension Institute {
    public enum CI {}
}

extension Institute.CI {
    public enum Application {}
}

extension Institute.CI.Application {
    /// The plan use case: classify one run's tier/legs/gating from event
    /// facts. A thin composition over `CI.Contract.Plan` for front ends.
    public enum Plan {
        public static func run(
            forcedTier: String, ref: String, headMessage: String,
            event: String, platformSupport: String, lintBundle: String
        ) throws(CI_Contract.CI.Contract.Plan.Error) -> CI_Contract.CI.Contract.Plan {
            try CI_Contract.CI.Contract.Plan(
                forcedTier: forcedTier, ref: ref, headMessage: headMessage,
                event: event, platformSupport: platformSupport,
                lintBundle: lintBundle)
        }
    }
}
