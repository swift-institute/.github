extension PRTransaction {
    static func verify(_ snapshot: Snapshot) throws {
        switch snapshot.plan.verification {
        case .package:
            let ci = snapshot.checks.filter { $0.name == "ci-ok" }
            guard !ci.isEmpty else { throw Error.missingCI }
            guard ci.allSatisfy({ terminal($0.conclusion) }) else { throw Error.staleCI }
            let currentCI = ci.filter { $0.head == snapshot.head }
            guard !currentCI.isEmpty,
                currentCI.allSatisfy({ $0.conclusion == "success" })
            else {
                throw Error.staleCI
            }

            let fullTier = snapshot.checks.filter { $0.name == "full-tier" }
            let currentFullTier = fullTier.filter { $0.head == snapshot.head }
            guard !fullTier.isEmpty,
                fullTier.allSatisfy({ terminal($0.conclusion) }),
                !currentFullTier.isEmpty,
                currentFullTier.allSatisfy({ $0.conclusion == "success" })
            else {
                throw Error.nonterminalFullTier
            }

        case .control(let names):
            guard !names.isEmpty,
                names.allSatisfy({ !$0.isEmpty }),
                Set(names).count == names.count
            else {
                throw Error.profile
            }

            for name in names {
                let supplied = snapshot.checks.filter { $0.name == name }
                guard !supplied.isEmpty else { throw Error.missing(name) }
                guard supplied.allSatisfy({ terminal($0.conclusion) }) else {
                    throw Error.nonterminal(name)
                }

                let current = supplied.filter { $0.head == snapshot.head }
                guard !current.isEmpty else { throw Error.stale(name) }
                guard current.allSatisfy({ $0.conclusion == "success" }) else {
                    throw Error.unsuccessful(name)
                }
            }
        }
    }

    private static func terminal(_ conclusion: String?) -> Bool {
        [
            "action_required", "cancelled", "failure", "neutral", "skipped", "stale",
            "startup_failure", "success", "timed_out",
        ].contains(conclusion ?? "")
    }
}
