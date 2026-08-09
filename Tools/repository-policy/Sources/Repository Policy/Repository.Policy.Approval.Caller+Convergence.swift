import Foundation

extension Repository.Policy.Approval.Caller {
    public static func decision(
        state: State,
        source: Data
    ) throws(Error) -> Decision {
        guard
            state.visibility == "private",
            !state.archived,
            !state.branch.isEmpty
        else {
            throw .invalidTarget(0)
        }
        guard state.file?.contents != source else { return .converged }
        return .pullRequest(base: state.branch, revision: state.file?.revision)
    }

    public static func converge(
        client: RepositoryPolicy.GitHubClient,
        targets: [String],
        source: Data,
        dryRun: Bool
    ) async throws(Error) -> Receipt {
        var seen = Set<String>()
        var proposed = 0
        var opened = 0

        for (offset, target) in targets.enumerated() {
            let ordinal = offset + 1
            guard valid(target) else {
                throw .invalidTarget(ordinal)
            }
            guard seen.insert(target).inserted else {
                throw .duplicateTarget(ordinal)
            }

            let state: State
            do {
                state = try await client.caller(for: target, path: path)
            } catch {
                throw .operation(ordinal)
            }
            let action: Decision
            do {
                action = try decision(state: state, source: source)
            } catch {
                throw .invalidTarget(ordinal)
            }
            guard case .pullRequest(let base, let revision) = action else { continue }
            proposed += 1
            guard !dryRun else { continue }

            do {
                let guarded = try await client.caller(for: target, path: path)
                guard try decision(state: guarded, source: source) == action else {
                    throw Error.operation(ordinal)
                }
                let created = try await client.proposeCaller(
                    at: path,
                    in: target,
                    base: base,
                    revision: revision,
                    contents: source
                )
                opened += created ? 1 : 0
            } catch let error as Error {
                throw error
            } catch {
                throw .operation(ordinal)
            }
        }

        return Receipt(
            examined: targets.count,
            proposed: proposed,
            opened: opened,
            dryRun: dryRun
        )
    }

    private static func valid(_ target: String) -> Bool {
        let parts = target.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let owner = parts[0]
        let name = parts[1]
        let first = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let allowed = first.union(Set("._-"))
        guard let ownerFirst = owner.first, first.contains(ownerFirst), !name.isEmpty else {
            return false
        }
        return owner.allSatisfy(allowed.contains) && name.allSatisfy(allowed.contains)
    }
}
