import Foundation
import Repository_Policy

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
enum Main {
    static func main() async {
        do {
            let arguments = try Arguments(CommandLine.arguments)
            guard let token = ProcessInfo.processInfo.environment["GH_TOKEN"], !token.isEmpty else {
                throw RepositoryPolicy.ConfigurationError("GH_TOKEN is required")
            }
            let api = ProcessInfo.processInfo.environment["GITHUB_API_URL"] ?? "https://api.github.com"
            guard let baseURL = URL(string: api) else {
                throw RepositoryPolicy.ConfigurationError("GITHUB_API_URL is invalid")
            }
            let scope = try RepositoryPolicy.Scope(
                organization: arguments.organization,
                repository: arguments.repository
            )
            let receipt = try await RepositoryPolicy.run(
                client: .init(token: token, baseURL: baseURL),
                configuration: .init(
                    scope: scope,
                    dryRun: arguments.dryRun,
                    journal: URL(filePath: arguments.journal),
                    receipt: URL(filePath: arguments.receipt)
                )
            )
            print(
                "repository-policy: scope=\(receipt.scope) examined=\(receipt.examined) " +
                    "eligible=\(receipt.eligible) converged=\(receipt.converged) " +
                    "enabled=\(receipt.enabled) would-enable=\(receipt.wouldEnable)"
            )
        } catch {
            FileHandle.standardError.write(
                Data("repository-policy: \(error)\n".utf8)
            )
            exit(1)
        }
    }

    private struct Arguments {
        var organization: String?
        var repository: String?
        var dryRun = true
        var journal: String
        var receipt: String

        init(_ arguments: [String]) throws {
            let temporary = FileManager.default.temporaryDirectory
            journal = temporary.appending(path: "repository-policy-journal.jsonl").path
            receipt = temporary.appending(path: "repository-policy-receipt.json").path

            var index = 1
            while index < arguments.count {
                let name = arguments[index]
                guard index + 1 < arguments.count else {
                    throw RepositoryPolicy.ConfigurationError("missing value for \(name)")
                }
                let value = arguments[index + 1]
                switch name {
                case "--organization":
                    organization = value
                case "--repository":
                    repository = value
                case "--dry-run":
                    guard let parsed = Bool(value) else {
                        throw RepositoryPolicy.ConfigurationError("--dry-run must be true or false")
                    }
                    dryRun = parsed
                case "--journal":
                    journal = value
                case "--receipt":
                    receipt = value
                default:
                    throw RepositoryPolicy.ConfigurationError("unknown argument \(name)")
                }
                index += 2
            }
        }
    }
}
