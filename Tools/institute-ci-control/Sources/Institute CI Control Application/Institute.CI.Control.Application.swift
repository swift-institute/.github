import Fleet_Convergence
import Fleet_Inventory
import GitHub_Control
import Private_Verification

// Nest.Name namespaces (FT1-ratification.json). The trusted control
// Application layer composes credentialed use cases; it owns no
// predicate and is never linked into ordinary/fork execution.
public enum Institute {}

extension Institute {
    public enum CI {}
}

extension Institute.CI {
    public enum Control {}
}

extension Institute.CI.Control {
    public enum Application {}
}

extension Institute.CI.Control.Application {
    /// The convergence-wave use case shell: binds a Fleet.Convergence
    /// plan to the journaled apply. Live wave execution arrives with
    /// F14; this Application owns orchestration shape only.
    public enum Converge {
        public static func begin(
            plan: Fleet.Convergence.Plan
        ) -> Fleet.Convergence.Apply {
            Fleet.Convergence.Apply(plan: plan)
        }

        public static func resume(
            plan: Fleet.Convergence.Plan,
            journal: [Fleet.Convergence.Apply.Entry]
        ) throws(Fleet.Convergence.Apply.Error) -> Fleet.Convergence.Resume.State {
            try Fleet.Convergence.Resume.from(plan: plan, journal: journal)
        }
    }
}
