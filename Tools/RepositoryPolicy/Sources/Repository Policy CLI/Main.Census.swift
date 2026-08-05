import Foundation
import Repository_Policy

extension Main {
    /// `repository-policy census --repo <name>=<root>=<headSha> ... --output <csv>`
    ///
    /// Regenerates the FT1 census from checked-out trees at the given heads
    /// (F1; swift-institute/.github#363). Deterministic sorted traversal;
    /// parity with the FT1 artifact is order-normalized.
    static func census(_ arguments: [String]) throws {
        var repos: [Repository.Policy.Census.Generator.Repo] = []
        var output: String?
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--repo":
                guard let value = iterator.next() else {
                    throw RepositoryPolicy.ConfigurationError("--repo needs <name>=<root>=<headSha>")
                }
                let parts = value.split(separator: "=", maxSplits: 2).map(String.init)
                guard parts.count == 3 else {
                    throw RepositoryPolicy.ConfigurationError("--repo needs <name>=<root>=<headSha>")
                }
                repos.append(.init(name: parts[0], root: parts[1], headSha: parts[2]))
            case "--output":
                output = iterator.next()
            default:
                throw RepositoryPolicy.ConfigurationError("unknown census argument \(argument)")
            }
        }
        guard let output, !repos.isEmpty else {
            throw RepositoryPolicy.ConfigurationError("census requires --repo … and --output")
        }
        let census = try Repository.Policy.Census.Generator(repos: repos).run()
        try Data(census.normalized.csv.utf8)
            .write(to: URL(fileURLWithPath: output))
        var byKind: [String: Int] = [:]
        for row in census.rows {
            byKind[row.coordinateKind.rawValue, default: 0] += 1
        }
        let summary = byKind.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("repository-policy: census rows=\(census.rows.count) \(summary)")
    }

    /// `repository-policy capability-records --output <json>` — emits the
    /// FT1-frozen D-01…D-12 capability records.
    static func capabilityRecords(_ arguments: [String]) throws {
        guard arguments.count == 2, arguments[0] == "--output" else {
            throw RepositoryPolicy.ConfigurationError("capability-records requires --output <path>")
        }
        try Repository.Policy.Capability.recordsJSON()
            .write(to: URL(fileURLWithPath: arguments[1]))
        print("repository-policy: capability-records count=\(Repository.Policy.Capability.records.count)")
    }
}
