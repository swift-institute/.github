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
        // swift-institute/.github#266 (control-plane surface reachability
        // follow-up, 2026-08-04): a `control-plane`-class repository's own
        // top-level CI workflow legitimately composes bespoke steps (e.g. a
        // matrix-enumeration job) alongside calls into a centralized
        // reusable — the exact shape swift-institute/Issues' ci.yml uses
        // (an `enumerate-issues` job with its own steps, feeding a
        // `per-issue` matrix job that calls the universal swift-ci.yml
        // reusable). Kind-inference (`ActionFile.init` below) has no
        // `workflow_call` trigger to key off for this shape, so the
        // inferred `action.kind` is `.thinCaller` regardless of grant; a
        // `.bespoke` grant is exempted from the `grant.kind != action.kind`
        // mismatch check (REPO-ACTIONS-002) and from the thin-caller
        // shape constraint (REPO-ACTIONS-005 only fires for
        // `grant.kind == .thinCaller`), while REPO-ACTIONS-003
        // (triggers) and REPO-ACTIONS-004 (direct `uses`) — the actual
        // security-relevant enforcement — remain fully in force against
        // the grant's explicit allowlists.
        case bespoke = "bespoke"
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

        public init(
            surface: Surface,
            repository: String,
            path: String,
            reason: String
        ) {
            self.surface = surface
            self.repository = repository
            self.path = path
            self.reason = reason
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case surface
            case repository
            case path
            case reason
        }

        public init(from decoder: Decoder) throws {
            let dynamicKeys = try decoder.container(keyedBy: DynamicCodingKey.self)
            let known = Set(CodingKeys.allCases.map(\.stringValue))
            for key in dynamicKeys.allKeys where !known.contains(key.stringValue) {
                throw RepositoryPolicy.ConfigurationError(
                    "surface exemption has unknown key: \(key.stringValue)"
                )
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.surface = try container.decode(Surface.self, forKey: .surface)
            self.repository = try container.decode(String.self, forKey: .repository)
            self.path = try container.decode(String.self, forKey: .path)
            self.reason = try container.decode(String.self, forKey: .reason)
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

        public static var instituteDefaultURL: URL {
            URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Policy/repository-surfaces.json")
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
        public let advisories: [SurfaceViolation]

        public var passed: Bool { violations.isEmpty }
    }

    public struct SurfaceSweepReport: Codable, Equatable, Sendable {
        public let reports: [SurfaceReport]

        public init(reports: [SurfaceReport]) {
            self.reports = reports.sorted { $0.repository < $1.repository }
        }

        public var passed: Bool {
            reports.allSatisfy(\.passed)
        }
    }

    public static func validateSurface(
        repository: String,
        repositoryClass: RepositoryClass,
        root: URL,
        policy: SurfacePolicy
    ) throws -> SurfaceReport {
        try validateSurface(
            repository: repository,
            repositoryClass: repositoryClass,
            snapshot: SurfaceSnapshot(root: root),
            policy: policy
        )
    }

    public static func validateSurface(
        repository: String,
        repositoryClass: RepositoryClass,
        files: [String: String],
        policy: SurfacePolicy
    ) throws -> SurfaceReport {
        try validateSurface(
            repository: repository,
            repositoryClass: repositoryClass,
            snapshot: SurfaceSnapshot(files: files),
            policy: policy
        )
    }

    private static func validateSurface(
        repository: String,
        repositoryClass: RepositoryClass,
        snapshot: SurfaceSnapshot,
        policy: SurfacePolicy
    ) throws -> SurfaceReport {
        guard repository.split(separator: "/", omittingEmptySubsequences: false).count == 2 else {
            throw ConfigurationError("repository must use owner/name form")
        }

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

            if grant.kind != action.kind, grant.kind != .bespoke {
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

        var advisories = [SurfaceViolation]()

        if snapshot.hasSPIYML {
            for file in snapshot.doccMarkdownFiles
            where file.contents.contains(doccPlaceholderMarker) {
                advisories.append(
                    .init(
                        identifier: "REPO-DOCS-001",
                        path: file.path,
                        message:
                            "DocC catalogue still carries the umbrella placeholder marker while .spi.yml publishes it to the Swift Package Index"
                    )
                )
            }
        }

        if let readme = snapshot.readmeContents {
            for line in stripFencedCodeBlocks(readme) {
                if containsStatusBadge(line: line) {
                    advisories.append(
                        .init(
                            identifier: "REPO-README-001",
                            path: "README.md",
                            message: "development-status badge (img.shields.io/badge/status-) is struck; remove it"
                        )
                    )
                }
                if isPlatformSupportHeading(line) {
                    advisories.append(
                        .init(
                            identifier: "REPO-README-002",
                            path: "README.md",
                            message:
                                "Platform Support section is struck; the platform matrix is derived from the manifest"
                        )
                    )
                }
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
            },
            advisories: advisories.sorted {
                if $0.path != $1.path { return $0.path < $1.path }
                if $0.identifier != $1.identifier { return $0.identifier < $1.identifier }
                return $0.message < $1.message
            }
        )
    }
}

private let doccPlaceholderMarker =
    "umbrella catalog placeholder. Replace this line with a one-sentence"

/// Removes fenced ``` ... ``` code blocks line-by-line (rather than a
/// dotall regex over the whole file) so lines outside a fence keep their
/// exact boundaries; returns the surviving lines in order.
private func stripFencedCodeBlocks(_ text: String) -> [Substring] {
    var lines = [Substring]()
    var inFence = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            inFence.toggle()
            continue
        }
        if inFence { continue }
        lines.append(line)
    }
    return lines
}

/// True when `line` contains a Markdown image (`![alt](url)`) whose target
/// URL contains the literal `img.shields.io/badge/status-`.
private func containsStatusBadge(line: Substring) -> Bool {
    var searchStart = line.startIndex
    while let altStart = line.range(of: "![", range: searchStart..<line.endIndex) {
        guard let altClose = line.range(of: "]", range: altStart.upperBound..<line.endIndex)
        else { break }
        guard altClose.upperBound < line.endIndex, line[altClose.upperBound] == "(" else {
            searchStart = altStart.upperBound
            continue
        }
        let urlStart = line.index(after: altClose.upperBound)
        guard let urlClose = line.range(of: ")", range: urlStart..<line.endIndex) else { break }
        let url = line[urlStart..<urlClose.lowerBound]
        if url.contains("img.shields.io/badge/status-") {
            return true
        }
        searchStart = urlClose.upperBound
    }
    return false
}

/// True when `line` matches `^#{2,6}[ \t]+Platform Support[ \t]*$`,
/// case-exact.
private func isPlatformSupportHeading(_ line: Substring) -> Bool {
    let characters = Array(line)
    var index = 0
    var hashCount = 0
    while index < characters.count, characters[index] == "#" {
        hashCount += 1
        index += 1
    }
    guard hashCount >= 2, hashCount <= 6 else { return false }
    guard index < characters.count, characters[index] == " " || characters[index] == "\t" else {
        return false
    }
    while index < characters.count, characters[index] == " " || characters[index] == "\t" {
        index += 1
    }
    let title = Array("Platform Support")
    guard characters.count - index >= title.count else { return false }
    for offset in title.indices where characters[index + offset] != title[offset] {
        return false
    }
    index += title.count
    while index < characters.count, characters[index] == " " || characters[index] == "\t" {
        index += 1
    }
    return index == characters.count
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

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private func normalized(path: String) -> String {
    path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
}

private struct DoccMarkdownFile {
    let path: String
    let contents: String
}

/// `**/*.docc/**/*.md`: an `.md` file with some path component before it
/// (anywhere, zero or more directories deep) that ends in `.docc`.
private func isDoccMarkdownPath(_ path: String) -> Bool {
    guard path.hasSuffix(".md") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count >= 2 else { return false }
    return components.dropLast().contains { $0.hasSuffix(".docc") }
}

private struct SurfaceSnapshot {
    let actions: [ActionFile]
    let issueForms: [String]
    let hasSPIYML: Bool
    let doccMarkdownFiles: [DoccMarkdownFile]
    let readmeContents: String?

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
        var hasSPIYML = false
        var doccMarkdownFiles = [DoccMarkdownFile]()
        var readmeContents: String?
        let rootPath = root.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = relativePath(url: url, rootPath: rootPath)

            if path.hasPrefix(".github/ISSUE_TEMPLATE/") {
                issueForms.append(path)
            }

            if path == ".spi.yml" {
                hasSPIYML = true
            }
            if path == "README.md" {
                readmeContents = try String(contentsOf: url, encoding: .utf8)
            }
            if isDoccMarkdownPath(path) {
                let contents = try String(contentsOf: url, encoding: .utf8)
                doccMarkdownFiles.append(DoccMarkdownFile(path: path, contents: contents))
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
        self.hasSPIYML = hasSPIYML
        self.doccMarkdownFiles = doccMarkdownFiles.sorted { $0.path < $1.path }
        self.readmeContents = readmeContents
    }

    init(files: [String: String]) throws {
        var actions = [ActionFile]()
        var issueForms = [String]()
        var hasSPIYML = false
        var doccMarkdownFiles = [DoccMarkdownFile]()
        var readmeContents: String?
        for (path, source) in files {
            if path.hasPrefix(".github/ISSUE_TEMPLATE/") {
                issueForms.append(path)
            }
            if path == ".spi.yml" {
                hasSPIYML = true
            }
            if path == "README.md" {
                readmeContents = source
            }
            if isDoccMarkdownPath(path) {
                doccMarkdownFiles.append(DoccMarkdownFile(path: path, contents: source))
            }
            let isWorkflow =
                path.hasPrefix(".github/workflows/")
                && (path.hasSuffix(".yml") || path.hasSuffix(".yaml"))
            let isAction =
                path.hasPrefix(".github/actions/")
                && (path.hasSuffix("/action.yml") || path.hasSuffix("/action.yaml"))
            if isWorkflow || isAction {
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
        self.hasSPIYML = hasSPIYML
        self.doccMarkdownFiles = doccMarkdownFiles.sorted { $0.path < $1.path }
        self.readmeContents = readmeContents
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
        var onChildIndent: Int?
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
                onChildIndent = nil
            }
            if inJobs, indent <= jobsIndent, normalizedKey(trimmed) != "jobs:" {
                finishJob()
                inJobs = false
            }

            if indent == 0, let value = value(after: "on", in: trimmed) {
                inOn = true
                onIndent = indent
                onChildIndent = nil
                for trigger in inlineValues(value) {
                    triggers.insert(trigger)
                }
                continue
            }
            if inOn, indent > onIndent, let key = mappingKey(trimmed) {
                if onChildIndent == nil {
                    onChildIndent = indent
                }
                if indent == onChildIndent {
                    triggers.insert(key)
                }
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
