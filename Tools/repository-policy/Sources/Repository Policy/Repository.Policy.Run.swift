import Foundation

extension RepositoryPolicy {
    public struct Scope: Equatable, Sendable {
        public let organization: String?
        public let repository: String?

        public init(organization: String?, repository: String?) throws {
            let organization = organization.flatMap { $0.isEmpty ? nil : $0 }
            let repository = repository.flatMap { $0.isEmpty ? nil : $0 }
            guard (organization == nil) != (repository == nil) else {
                throw ConfigurationError(
                    "exactly one of --organization or --repository is required"
                )
            }
            let owner = repository.map { String($0.prefix { $0 != "/" }) } ?? organization!
            guard owner != "tenthijeboonkkamp" else {
                throw ConfigurationError("owner tenthijeboonkkamp is outside Institute scope")
            }
            if let repository, repository.split(separator: "/", omittingEmptySubsequences: false).count != 2 {
                throw ConfigurationError("--repository must use owner/name form")
            }
            self.organization = organization
            self.repository = repository
        }
    }

    public struct Configuration: Sendable {
        public let scope: Scope
        public let dryRun: Bool
        public let journal: URL
        public let receipt: URL

        public init(scope: Scope, dryRun: Bool, journal: URL, receipt: URL) {
            self.scope = scope
            self.dryRun = dryRun
            self.journal = journal
            self.receipt = receipt
        }
    }

    public struct Receipt: Codable, Equatable, Sendable {
        public let scope: String
        public let dryRun: Bool
        public let examined: Int
        public let eligible: Int
        public let excluded: [String: Int]
        public let converged: Int
        public let enabled: Int
        public let wouldEnable: Int
        public let verifiedRepositories: [String]
    }

    public struct ConfigurationError: Swift.Error, CustomStringConvertible, Sendable {
        public let description: String

        public init(_ description: String) {
            self.description = description
        }
    }

    public static func run(
        client: GitHubClient,
        configuration: Configuration
    ) async throws -> Receipt {
        let repositories: [Repository]
        let scopeDescription: String
        if let fullName = configuration.scope.repository {
            repositories = [try await client.repository(fullName)]
            scopeDescription = fullName
        } else {
            let organization = configuration.scope.organization!
            repositories = try await client.repositories(organization: organization)
            scopeDescription = organization
        }

        let journal = try Journal(url: configuration.journal)
        var excluded = [String: Int]()
        var eligible = 0
        var converged = 0
        var enabled = 0
        var wouldEnable = 0
        var verified = [String]()

        for repository in repositories.sorted(by: { $0.fullName < $1.fullName }) {
            if let reason = staticExclusion(of: repository) {
                excluded[reason.rawValue, default: 0] += 1
                continue
            }

            let manifestKind = try await client.rootManifestKind(repository.fullName)
            guard manifestKind == "file" else {
                let reason: Exclusion =
                    manifestKind == nil ? .missingRootManifest : .rootManifestNotFile
                excluded[reason.rawValue, default: 0] += 1
                continue
            }

            eligible += 1
            let state = try await client.vulnerabilityReporting(repository.fullName)
            switch decision(
                for: repository,
                manifestKind: manifestKind,
                vulnerabilityReporting: state
            ) {
            case .excluded(let reason):
                excluded[reason.rawValue, default: 0] += 1
            case .converged:
                converged += 1
                verified.append(repository.fullName)
                try journal.append(repository: repository.fullName, phase: "verified-existing")
            case .enable:
                if configuration.dryRun {
                    wouldEnable += 1
                    try journal.append(repository: repository.fullName, phase: "would-enable")
                    continue
                }
                try journal.append(repository: repository.fullName, phase: "prepared")
                try await client.enableVulnerabilityReporting(repository.fullName)
                try journal.append(repository: repository.fullName, phase: "accepted")
                try await verifyEnabled(client: client, repository: repository.fullName)
                try journal.append(repository: repository.fullName, phase: "verified-enabled")
                enabled += 1
                verified.append(repository.fullName)
            }
        }

        // An explicitly named repository that turns out excluded (not
        // public, archived, a fork, empty, or missing a root manifest) is a
        // legitimate GitHub-side fact, not an operator mistake — a typo or
        // out-of-scope owner already fails earlier, in `Scope.init` or the
        // repository fetch above. Report the divergence through `excluded`
        // on the receipt below rather than failing the whole dispatch
        // (swift-institute/.github#160).

        let receipt = Receipt(
            scope: scopeDescription,
            dryRun: configuration.dryRun,
            examined: repositories.count,
            eligible: eligible,
            excluded: excluded,
            converged: converged,
            enabled: enabled,
            wouldEnable: wouldEnable,
            verifiedRepositories: verified.sorted()
        )
        try write(receipt, to: configuration.receipt)
        return receipt
    }

    public static func validateSurfaces(
        client: GitHubClient,
        scope: Scope,
        policy: SurfacePolicy
    ) async throws -> SurfaceSweepReport {
        let repositories: [Repository]
        if let fullName = scope.repository {
            repositories = [try await client.repository(fullName)]
        } else {
            repositories = try await client.repositories(
                organization: scope.organization!
            )
        }

        var reports = [SurfaceReport]()
        for repository in repositories.sorted(by: { $0.fullName < $1.fullName }) {
            guard staticExclusion(of: repository) == nil else { continue }
            guard try await client.rootManifestKind(repository.fullName) == "file" else {
                continue
            }
            let repositoryClass =
                policy.actionGrants
                .first { $0.repository == repository.fullName }?
                .repositoryClass ?? .package
            reports.append(
                try validateSurface(
                    repository: repository.fullName,
                    repositoryClass: repositoryClass,
                    files: try await client.surfaceFiles(repository.fullName),
                    policy: policy
                )
            )
        }
        return SurfaceSweepReport(reports: reports)
    }

    private static func verifyEnabled(
        client: GitHubClient,
        repository: String
    ) async throws {
        for attempt in 1...6 {
            if try await client.vulnerabilityReporting(repository) == .enabled {
                return
            }
            guard attempt < 6 else {
                throw ConfigurationError(
                    "\(repository): PVR was not enabled after accepted PUT"
                )
            }
            try await Task<Never, Never>.sleep(for: .seconds(1))
        }
    }

    private static func write(_ receipt: Receipt, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(receipt)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private final class Journal {
        private let handle: FileHandle

        init(url: URL) throws {
            let manager = FileManager.default
            if !manager.fileExists(atPath: url.path) {
                guard manager.createFile(atPath: url.path, contents: nil) else {
                    throw ConfigurationError("could not create journal at \(url.path)")
                }
            }
            handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
        }

        deinit {
            try? handle.close()
        }

        func append(repository: String, phase: String) throws {
            let record = JournalRecord(repository: repository, phase: phase)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(record)
            data.append(0x0A)
            try handle.write(contentsOf: data)
            try handle.synchronize()
        }
    }

    private struct JournalRecord: Codable {
        let repository: String
        let phase: String
    }
}
