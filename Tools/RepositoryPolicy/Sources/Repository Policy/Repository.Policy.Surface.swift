import Foundation

extension RepositoryPolicy {
    public enum RepositoryClass: String, Codable, Sendable {
        case package
        case tool
        case controlPlane = "control-plane"
    }

    public enum Surface: String, Codable, Sendable {
        case actions
        case issueForms = "issue-forms"
    }

    public enum ActionGrantKind: String, Codable, Sendable {
        case thinCaller = "thin-caller"
        case toolWorkflow = "tool-workflow"
        case toolAction = "tool-action"
    }

    public struct ActionGrant: Codable, Equatable, Sendable {
        public let repositoryClass: RepositoryClass
        public let repository: String?
        public let path: String
        public let kind: ActionGrantKind
        public let triggers: [String]
        public let uses: [String]

        public init(
            repositoryClass: RepositoryClass,
            repository: String? = nil,
            path: String,
            kind: ActionGrantKind,
            triggers: [String],
            uses: [String]
        ) {
            self.repositoryClass = repositoryClass
            self.repository = repository
            self.path = path
            self.kind = kind
            self.triggers = triggers
            self.uses = uses
        }
    }

    public struct SurfaceExemption: Codable, Equatable, Sendable {
        public let surface: Surface
        public let repository: String
        public let path: String
        public let reason: String
        public let reviewAfter: String?

        public init(
            surface: Surface,
            repository: String,
            path: String,
            reason: String,
            reviewAfter: String? = nil
        ) {
            self.surface = surface
            self.repository = repository
            self.path = path
            self.reason = reason
            self.reviewAfter = reviewAfter
        }
    }

    public struct SurfacePolicy: Codable, Equatable, Sendable {
        public let schemaVersion: Int
        public let actionGrants: [ActionGrant]
        public let exemptions: [SurfaceExemption]

        public init(
            schemaVersion: Int,
            actionGrants: [ActionGrant],
            exemptions: [SurfaceExemption]
        ) {
            self.schemaVersion = schemaVersion
            self.actionGrants = actionGrants
            self.exemptions = exemptions
        }

        public static func load(from url: URL) throws -> Self {
            let policy = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard policy.schemaVersion == 1 else {
                throw ConfigurationError(
                    "unsupported repository surface policy schema \(policy.schemaVersion)"
                )
            }
            for grant in policy.actionGrants {
                guard normalized(path: grant.path) == grant.path else {
                    throw ConfigurationError("action grant path is not normalized: \(grant.path)")
                }
                guard !grant.path.isEmpty else {
                    throw ConfigurationError("action grant path must not be empty")
                }
                if let repository = grant.repository {
                    try validate(repository: repository)
                }
            }
            for exemption in policy.exemptions {
                try validate(repository: exemption.repository)
                guard normalized(path: exemption.path) == exemption.path else {
                    throw ConfigurationError(
                        "surface exemption path is not normalized: \(exemption.path)"
                    )
                }
                guard !exemption.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ConfigurationError(
                        "surface exemption requires a reason: \(exemption.repository) \(exemption.path)"
                    )
                }
            }
            return policy
        }

        private static func validate(repository: String) throws {
            guard
                repository.split(separator: "/", omittingEmptySubsequences: false).count == 2
            else {
                throw ConfigurationError("repository must use owner/name form: \(repository)")
            }
        }
    }

    public struct SurfaceViolation: Codable, Equatable, Sendable {
        public let identifier: String
        public let path: String
        public let message: String

        public init(identifier: String, path: String, message: String) {
            self.identifier = identifier
            self.path = path
            self.message = message
        }
    }

    public struct SurfaceReport: Codable, Equatable, Sendable {
        public let repository: String
        public let repositoryClass: RepositoryClass
        public let actionFiles: Int
        public let issueFormFiles: Int
        public let exemptionsApplied: Int
        public let violations: [SurfaceViolation]

        public var passed: Bool { violations.isEmpty }
    }

    public static func validateSurface(
        repository: String,
        repositoryClass: RepositoryClass,
        root: URL,
        policy: SurfacePolicy
    ) throws -> SurfaceReport {
        guard repository.split(separator: "/", omittingEmptySubsequences: false).count == 2 else {
            throw ConfigurationError("repository must use owner/name form")
        }

        let snapshot = try SurfaceSnapshot(root: root)
        var violations = [SurfaceViolation]()
        var exemptionsApplied = 0

        for action in snapshot.actions {
            if policy.exempts(surface: .actions, repository: repository, path: action.path) {
                exemptionsApplied += 1
                continue
            }
            let grants = policy.actionGrants.filter {
                $0.repositoryClass == repositoryClass
                    && ($0.repository == nil || $0.repository == repository)
                    && $0.path == action.path
            }
            guard let grant = grants.only else {
                violations.append(
                    .init(
                        identifier: "REPO-ACTIONS-001",
                        path: action.path,
                        message: "package-local Actions are denied without an exact typed grant"
                    )
                )
                continue
            }

            if grant.kind != action.kind {
                violations.append(
                    .init(
                        identifier: "REPO-ACTIONS-002",
                        path: action.path,
                        message: "expected \(grant.kind.rawValue), found \(action.kind.rawValue)"
                    )
                )
            }

            let allowedTriggers = Set(grant.triggers)
            for trigger in action.triggers where !allowedTriggers.contains(trigger) {
                violations.append(
                    .init(
                        identifier: "REPO-ACTIONS-003",
                        path: action.path,
                        message: "trigger '\(trigger)' is not granted"
                    )
                )
            }

            let allowedUses = Set(grant.uses)
            for use in action.uses where !allowedUses.contains(use) {
                violations.append(
                    .init(
                        identifier: "REPO-ACTIONS-004",
                        path: action.path,
                        message: "direct use '\(use)' is not granted"
                    )
                )
            }

            if grant.kind == .thinCaller {
                if action.hasSteps || action.hasRunsOn || action.jobCount == 0
                    || action.jobsWithUses != action.jobCount
                {
                    violations.append(
                        .init(
                            identifier: "REPO-ACTIONS-005",
                            path: action.path,
                            message: "thin callers require every job to use a reusable workflow and forbid steps/runs-on"
                        )
                    )
                }
            }
            if grant.kind == .toolWorkflow, !action.triggers.contains("workflow_call") {
                violations.append(
                    .init(
                        identifier: "REPO-ACTIONS-006",
                        path: action.path,
                        message: "tool-owned reusable workflows require workflow_call"
                    )
                )
            }
        }

        for path in snapshot.issueForms {
            if policy.exempts(surface: .issueForms, repository: repository, path: path) {
                exemptionsApplied += 1
            } else {
                violations.append(
                    .init(
                        identifier: "REPO-FORMS-001",
                        path: path,
                        message: "package-local Issue Forms are denied; use organization defaults"
                    )
                )
            }
        }

        return .init(
            repository: repository,
            repositoryClass: repositoryClass,
            actionFiles: snapshot.actions.count,
            issueFormFiles: snapshot.issueForms.count,
            exemptionsApplied: exemptionsApplied,
            violations: violations.sorted {
                if $0.path != $1.path { return $0.path < $1.path }
                if $0.identifier != $1.identifier { return $0.identifier < $1.identifier }
                return $0.message < $1.message
            }
        )
    }
}

private extension RepositoryPolicy.SurfacePolicy {
    func exempts(
        surface: RepositoryPolicy.Surface,
        repository: String,
        path: String
    ) -> Bool {
        exemptions.contains {
            $0.surface == surface && $0.repository == repository && $0.path == path
        }
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}

private func normalized(path: String) -> String {
    path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
}

private struct SurfaceSnapshot {
    let actions: [ActionFile]
    let issueForms: [String]

    init(root: URL) throws {
        let manager = FileManager.default
        guard
            let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
        else {
            throw RepositoryPolicy.ConfigurationError("cannot enumerate repository root \(root.path)")
        }

        var actions = [ActionFile]()
        var issueForms = [String]()
        let rootPath = root.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = relativePath(url: url, rootPath: rootPath)

            if path.hasPrefix(".github/ISSUE_TEMPLATE/") {
                issueForms.append(path)
            }

            let isWorkflow =
                path.hasPrefix(".github/workflows/")
                && (url.pathExtension == "yml" || url.pathExtension == "yaml")
            let isAction =
                path.hasPrefix(".github/actions/")
                && (url.lastPathComponent == "action.yml" || url.lastPathComponent == "action.yaml")
            if isWorkflow || isAction {
                let source = try String(contentsOf: url, encoding: .utf8)
                actions.append(
                    try ActionFile(
                        path: path,
                        source: source,
                        manifestIsAction: isAction
                    )
                )
            }
        }
        self.actions = actions.sorted { $0.path < $1.path }
        self.issueForms = issueForms.sorted()
    }
}

private func relativePath(url: URL, rootPath: String) -> String {
    let path = url.standardizedFileURL.path
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return String(path.dropFirst(prefix.count))
}

private struct ActionFile {
    let path: String
    let kind: RepositoryPolicy.ActionGrantKind
    let triggers: [String]
    let uses: [String]
    let hasSteps: Bool
    let hasRunsOn: Bool
    let jobCount: Int
    let jobsWithUses: Int

    init(path: String, source: String, manifestIsAction: Bool) throws {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var triggers = Set<String>()
        var uses = Set<String>()
        var hasSteps = false
        var hasRunsOn = false
        var inOn = false
        var onIndent = 0
        var inJobs = false
        var jobsIndent = 0
        var currentJobIndent: Int?
        var currentJobHasUse = false
        var jobCount = 0
        var jobsWithUses = 0

        func finishJob() {
            if currentJobIndent != nil, currentJobHasUse {
                jobsWithUses += 1
            }
            currentJobIndent = nil
            currentJobHasUse = false
        }

        for rawLine in lines {
            let line = stripComment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indent = line.prefix { $0 == " " }.count

            if inOn, indent <= onIndent {
                inOn = false
            }
            if inJobs, indent <= jobsIndent, normalizedKey(trimmed) != "jobs:" {
                finishJob()
                inJobs = false
            }

            if indent == 0, let value = value(after: "on", in: trimmed) {
                inOn = true
                onIndent = indent
                for trigger in inlineValues(value) {
                    triggers.insert(trigger)
                }
                continue
            }
            if inOn, indent > onIndent, let key = mappingKey(trimmed) {
                triggers.insert(key)
            }

            if indent == 0, normalizedKey(trimmed) == "jobs:" {
                inJobs = true
                jobsIndent = indent
                continue
            }
            if inJobs, indent == jobsIndent + 2, mappingKey(trimmed) != nil {
                finishJob()
                currentJobIndent = indent
                jobCount += 1
                continue
            }

            if normalizedKey(trimmed) == "steps:" {
                hasSteps = true
            }
            if value(after: "runs-on", in: trimmed) != nil {
                hasRunsOn = true
            }
            if let invocation = value(after: "uses", in: trimmed), !invocation.isEmpty {
                uses.insert(unquote(invocation))
                if currentJobIndent != nil {
                    currentJobHasUse = true
                }
            }
        }
        finishJob()

        let kind: RepositoryPolicy.ActionGrantKind
        if manifestIsAction {
            kind = .toolAction
        } else if triggers.contains("workflow_call") {
            kind = .toolWorkflow
        } else {
            kind = .thinCaller
        }

        guard manifestIsAction || !triggers.isEmpty else {
            throw RepositoryPolicy.ConfigurationError("\(path): workflow has no parseable trigger")
        }

        self.path = path
        self.kind = kind
        self.triggers = triggers.sorted()
        self.uses = uses.sorted()
        self.hasSteps = hasSteps
        self.hasRunsOn = hasRunsOn
        self.jobCount = jobCount
        self.jobsWithUses = jobsWithUses
    }
}

private func stripComment(_ line: String) -> String {
    var quote: Character?
    for index in line.indices {
        let character = line[index]
        if character == "\"" || character == "'" {
            quote = quote == character ? nil : (quote == nil ? character : quote)
        } else if character == "#", quote == nil {
            return String(line[..<index])
        }
    }
    return line
}

private func normalizedKey(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
}

private func mappingKey(_ value: String) -> String? {
    guard let colon = value.firstIndex(of: ":") else { return nil }
    let key = unquote(String(value[..<colon]).trimmingCharacters(in: .whitespaces))
    guard !key.isEmpty, !key.hasPrefix("-") else { return nil }
    return key
}

private func value(after key: String, in line: String) -> String? {
    guard let colon = line.firstIndex(of: ":") else { return nil }
    var candidate = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
    if candidate.hasPrefix("- ") {
        candidate.removeFirst(2)
    }
    candidate = unquote(candidate)
    guard candidate == key else { return nil }
    return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
}

private func inlineValues(_ value: String) -> [String] {
    let unwrapped = value.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
    guard !unwrapped.isEmpty else { return [] }
    return unwrapped.split(separator: ",").map {
        unquote(String($0).trimmingCharacters(in: .whitespaces))
    }
}

private func unquote(_ value: String) -> String {
    var value = value
    if value.count >= 2,
        let first = value.first,
        let last = value.last,
        (first == "\"" && last == "\"") || (first == "'" && last == "'")
    {
        value.removeFirst()
        value.removeLast()
    }
    return value
}
