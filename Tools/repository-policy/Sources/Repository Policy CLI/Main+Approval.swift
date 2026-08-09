import Foundation
import Repository_Policy

extension Main {
    static func approval(
        _ arguments: Approval.Arguments
    ) async throws {
        guard let token = ProcessInfo.processInfo.environment["GH_TOKEN"], !token.isEmpty else {
            throw RepositoryPolicy.ConfigurationError("GH_TOKEN is required")
        }
        let api = ProcessInfo.processInfo.environment["GITHUB_API_URL"] ?? "https://api.github.com"
        guard let baseURL = URL(string: api) else {
            throw RepositoryPolicy.ConfigurationError("GITHUB_API_URL is invalid")
        }
        let targetText = try String(
            contentsOf: URL(filePath: arguments.targets),
            encoding: .utf8
        )
        let targets = targetText
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        let source = try Data(contentsOf: URL(filePath: arguments.source))
        let receipt = try await Repository.Policy.Approval.Caller.converge(
            client: .init(token: token, baseURL: baseURL),
            targets: targets,
            source: source,
            dryRun: arguments.dryRun
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(receipt)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
