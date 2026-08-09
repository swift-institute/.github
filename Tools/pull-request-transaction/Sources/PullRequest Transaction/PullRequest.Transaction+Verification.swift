import Foundation

extension PullRequest.Transaction {
    static func verify(_ snapshot: Snapshot) throws {
        switch snapshot.plan.verification {
        case .package:
            // Check-run names are caller-path-prefixed. Renamed
            // swift-institute/.github#276 Task 3-01: the thin caller's `ci`
            // job used to render a layer wrapper's now-temporary
            // compatibility aggregate as `ci / ci-ok`; the required context
            // is now the universal chain's own aggregate, `ci / matrix /
            // ci-ok`, rendered through the wrapper's `matrix` job. This is
            // the PUBLIC package contract only — a private package's
            // required context is `verification / workspace` (Task
            // 2-01/2-02, #253) and is verified through the `.control`
            // profile with that name declared explicitly, not through this
            // case.
            let ciName = "ci / matrix / ci-ok"
            guard snapshot.checks.contains(where: { $0.name == ciName }) else {
                throw Error.missingCI
            }
            let ci = try latest(snapshot.checks, named: ciName)
            guard ci.head == snapshot.head,
                terminal(ci.conclusion),
                ci.conclusion == "success"
            else { throw Error.staleCI }

            let fullTierName = "full-tier"
            guard snapshot.checks.contains(where: { $0.name == fullTierName }) else {
                throw Error.nonterminalFullTier
            }
            let fullTier = try latest(snapshot.checks, named: fullTierName)
            guard fullTier.head == snapshot.head,
                terminal(fullTier.conclusion),
                fullTier.conclusion == "success"
            else { throw Error.nonterminalFullTier }

        case .control(let names):
            guard !names.isEmpty,
                names.allSatisfy({ !$0.isEmpty }),
                Set(names).count == names.count
            else {
                throw Error.profile
            }

            for name in names {
                guard snapshot.checks.contains(where: { $0.name == name }) else {
                    throw Error.missing(name)
                }
                let supplied = try latest(snapshot.checks, named: name)
                guard terminal(supplied.conclusion) else {
                    throw Error.nonterminal(name)
                }
                guard supplied.head == snapshot.head else { throw Error.stale(name) }
                guard supplied.conclusion == "success" else {
                    throw Error.unsuccessful(name)
                }
            }

        case .reviewOnly:
            // Fail-closed: satisfied only when NO check run — including a
            // synthesized `full-tier` entry — is cited at the exact head.
            // Any check present is an uncited check standing in for the
            // review this profile does not admit.
            guard snapshot.checks.filter({ $0.head == snapshot.head }).isEmpty else {
                throw Error.uncitedChecks
            }

        case .waveMechanical(let names, let mechanical):
            // The mechanical-remediation class attestation is a second,
            // independent gate from profile selection: a plan cannot admit
            // this fast lane by choosing the case alone.
            guard mechanical else { throw Error.profile }
            guard !names.isEmpty,
                names.allSatisfy({ !$0.isEmpty }),
                Set(names).count == names.count
            else {
                throw Error.profile
            }

            // Deliberately no full-tier requirement: the mandatory
            // post-merge full tier (verify-post-merge.yml) is the deferred
            // gate for this profile.
            for name in names {
                guard snapshot.checks.contains(where: { $0.name == name }) else {
                    throw Error.missing(name)
                }
                let supplied = try latest(snapshot.checks, named: name)
                guard terminal(supplied.conclusion) else {
                    throw Error.nonterminal(name)
                }
                guard supplied.head == snapshot.head else { throw Error.stale(name) }
                guard supplied.conclusion == "success" else {
                    throw Error.unsuccessful(name)
                }
            }
        }
    }

    /// Selects exactly one newest attempt for a required context. GitHub's
    /// authoritative start time establishes chronology and must identify one
    /// attempt. Equal newest start times are ambiguous API evidence; immutable
    /// IDs and rerun attempt ordinals must not break that tie. Repeated attempt
    /// identities are likewise refused even when their payloads agree.
    private static func latest(
        _ checks: [Snapshot.Check],
        named name: String
    ) throws(Error) -> Snapshot.Check {
        let supplied = checks.filter { $0.name == name }
        let formatter = ISO8601DateFormatter()
        let dated = supplied.compactMap { check in
            formatter.date(from: check.startedAt).map { (check, $0) }
        }
        let identities = Set(supplied.map { "\($0.id):\($0.attempt)" })
        guard dated.count == supplied.count,
            supplied.allSatisfy({ $0.id > 0 && $0.attempt > 0 }),
            identities.count == supplied.count,
            let newest = dated.map({ $0.1 }).max(),
            let selected = dated.first(where: { $0.1 == newest }),
            dated.filter({ $0.1 == newest }).count == 1
        else {
            throw Error.ambiguous(name)
        }
        return selected.0
    }

    private static func terminal(_ conclusion: String?) -> Bool {
        [
            "action_required", "cancelled", "failure", "neutral", "skipped", "stale",
            "startup_failure", "success", "timed_out",
        ].contains(conclusion ?? "")
    }
}
