import Foundation

public enum RepositoryPolicy {}

extension RepositoryPolicy {
    public struct Repository: Codable, Equatable, Sendable {
        public let id: Int64
        public let name: String
        public let fullName: String
        public let visibility: String
        public let archived: Bool
        public let disabled: Bool
        public let fork: Bool
        public let size: Int

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case fullName = "full_name"
            case visibility
            case archived
            case disabled
            case fork
            case size
        }

        public init(
            id: Int64,
            name: String,
            fullName: String,
            visibility: String,
            archived: Bool,
            disabled: Bool,
            fork: Bool,
            size: Int
        ) {
            self.id = id
            self.name = name
            self.fullName = fullName
            self.visibility = visibility
            self.archived = archived
            self.disabled = disabled
            self.fork = fork
            self.size = size
        }

        public var owner: String {
            String(fullName.prefix { $0 != "/" })
        }
    }

    public enum Exclusion: String, Codable, Equatable, Sendable {
        case deniedOwner = "denied-owner"
        case notPublic = "not-public"
        case archived
        case disabled
        case fork
        case empty
        case missingRootManifest = "missing-root-manifest"
        case rootManifestNotFile = "root-manifest-not-file"
    }

    public enum VulnerabilityReporting: String, Codable, Equatable, Sendable {
        case disabled
        case enabled
    }

    public enum Decision: Equatable, Sendable {
        case excluded(Exclusion)
        case converged
        case enable
    }

    public static func staticExclusion(
        of repository: Repository
    ) -> Exclusion? {
        guard repository.owner != "tenthijeboonkkamp" else {
            return .deniedOwner
        }
        guard repository.visibility == "public" else {
            return .notPublic
        }
        guard !repository.archived else { return .archived }
        guard !repository.disabled else { return .disabled }
        guard !repository.fork else { return .fork }
        guard repository.size > 0 else { return .empty }
        return nil
    }

    public static func decision(
        for repository: Repository,
        manifestKind: String?,
        vulnerabilityReporting: VulnerabilityReporting?
    ) -> Decision {
        if let exclusion = staticExclusion(of: repository) {
            return .excluded(exclusion)
        }
        guard let manifestKind else {
            return .excluded(.missingRootManifest)
        }
        guard manifestKind == "file" else {
            return .excluded(.rootManifestNotFile)
        }
        switch vulnerabilityReporting {
        case .enabled:
            return .converged
        case .disabled:
            return .enable
        case nil:
            return .excluded(.missingRootManifest)
        }
    }
}
