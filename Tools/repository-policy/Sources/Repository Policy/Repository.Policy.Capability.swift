import Foundation

extension Repository.Policy {
    /// The FT1-frozen concept/sole-owner capability records (PROGRAMME.md
    /// §9/§11, spellings per naming-annex-nest-name.md).
    public struct Capability: Codable, Sendable, Equatable {
        public let id: String
        public let concept: String
        public let domainOwner: String
        public let target: String
        public let namespace: String
        public let forbiddenDuplicate: String

        public init(
            id: String, concept: String, domainOwner: String,
            target: String, namespace: String, forbiddenDuplicate: String
        ) {
            self.id = id
            self.concept = concept
            self.domainOwner = domainOwner
            self.target = target
            self.namespace = namespace
            self.forbiddenDuplicate = forbiddenDuplicate
        }

        public static let records: [Capability] = [
            Capability(id: "D-01",
                       concept: "package identity, effective inventory, layer, dependency graph, SwiftPM and package operations",
                       domainOwner: "Workspace", target: "Workspace targets",
                       namespace: "Workspace.*",
                       forbiddenDuplicate: "raw SwiftPM or local manifest/layer parsers in Institute CI"),
            Capability(id: "D-02",
                       concept: "Swift syntax/AST rules and diagnostics",
                       domainOwner: "swift-linter", target: "swift-linter targets",
                       namespace: "swift-linter typed diagnostics",
                       forbiddenDuplicate: "Python/regex source rules"),
            Capability(id: "D-03",
                       concept: "repository, routing row, workflow/action and ruleset projection policy",
                       domainOwner: "Repository.Policy", target: "Repository Policy",
                       namespace: "Repository.Policy.*",
                       forbiddenDuplicate: "handwritten semantic YAML or wrapper-owned layer policy"),
            Capability(id: "D-04",
                       concept: "subject, event, platform, plan, aggregate and required check",
                       domainOwner: "CI.Contract", target: "CI Contract",
                       namespace: "CI.Contract.*",
                       forbiddenDuplicate: "workflow matrix or shell aggregate semantics"),
            Capability(id: "D-05",
                       concept: "canonical evidence, measurement, provenance, receipt and readiness",
                       domainOwner: "Institute.Receipt", target: "Institute Receipt",
                       namespace: "Institute.Receipt.*",
                       forbiddenDuplicate: "Python receipt producers/validators"),
            Capability(id: "D-06",
                       concept: "GitHub REST/GraphQL/App authentication/pagination/retry relation",
                       domainOwner: "GitHub.Control", target: "GitHub Control",
                       namespace: "GitHub.Control.*",
                       forbiddenDuplicate: "gh/curl/jq policy clients"),
            Capability(id: "D-07",
                       concept: "fleet census and durable convergence",
                       domainOwner: "Fleet.Inventory and Fleet.Convergence",
                       target: "Fleet Inventory + Fleet Convergence",
                       namespace: "Fleet.Inventory.* + Fleet.Convergence.*",
                       forbiddenDuplicate: "workflow-owned sweep/convergence"),
            Capability(id: "D-08",
                       concept: "private request, lease, exact-head verification, redaction and safe publication",
                       domainOwner: "Private.Verification", target: "Private Verification",
                       namespace: "Private.Verification.*",
                       forbiddenDuplicate: "credential-bearing subject jobs"),
            Capability(id: "D-09",
                       concept: "pull-request transaction",
                       domainOwner: "PullRequest.Transaction", target: "PullRequest Transaction",
                       namespace: "PullRequest.Transaction.*",
                       forbiddenDuplicate: "workflow GraphQL transaction logic"),
            Capability(id: "D-10",
                       concept: "programme work-item governance",
                       domainOwner: "Programme.Policy", target: "Programme Policy",
                       namespace: "Programme.Policy.*",
                       forbiddenDuplicate: "issue-specific shell"),
            Capability(id: "D-11",
                       concept: "credential-free command orchestration",
                       domainOwner: "Institute CI Application", target: "Institute CI Application",
                       namespace: "Institute.CI.Application.*",
                       forbiddenDuplicate: "predicate ownership in CLI/UI"),
            Capability(id: "D-12",
                       concept: "credentialed command orchestration",
                       domainOwner: "Institute CI Control Application",
                       target: "Institute CI Control Application",
                       namespace: "Institute.CI.Control.Application.*",
                       forbiddenDuplicate: "control libraries in ordinary/fork closure"),
        ]

        public static func recordsJSON() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(records)
        }
    }
}
