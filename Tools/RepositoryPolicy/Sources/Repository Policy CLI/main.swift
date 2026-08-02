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
            if CommandLine.arguments.dropFirst().first == "validate" {
                try validate(ValidationArguments(Array(CommandLine.arguments.dropFirst(2))))
            } else if CommandLine.arguments.dropFirst().first == "compact" {
                try await compact(CompactionArguments(Array(CommandLine.arguments.dropFirst(2))))
            } else {
                try await reconcile(ReconcileArguments(CommandLine.arguments))
            }
        } catch {
            FileHandle.standardError.write(Data("repository-policy: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func compact(_ arguments: CompactionArguments) async throws {
        guard let token = ProcessInfo.processInfo.environment["GH_TOKEN"], !token.isEmpty else {
            throw RepositoryPolicy.ConfigurationError("GH_TOKEN is required")
        }
        let api = ProcessInfo.processInfo.environment["GITHUB_API_URL"] ?? "https://api.github.com"
        guard let baseURL = URL(string: api) else {
            throw RepositoryPolicy.ConfigurationError("GITHUB_API_URL is invalid")
        }
        let expected = try RepositoryPolicy.Issue.Guard(
            revision: arguments.revision,
            digest: arguments.digest
        )
        let plan = try await RepositoryPolicy.GitHubClient(token: token, baseURL: baseURL).compactIssue(
            arguments.repository,
            number: arguments.issue,
            guard: expected,
            apply: arguments.apply
        )
        guard let plan else {
            print("repository-policy: compact already-converged")
            return
        }
        print(
            "repository-policy: compact \(arguments.apply ? "applied" : "dry-run") "
                + "revision=\(plan.guard.revision) digest=\(plan.guard.digest)"
        )
    }

    private static func reconcile(_ arguments: ReconcileArguments) async throws {
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
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: URL(filePath: arguments.surfacePolicy)
        )
        let report = try await RepositoryPolicy.validateSurfaces(
            client: .init(token: token, baseURL: baseURL),
            scope: scope,
            policy: policy
        )
        try write(report, to: arguments.surfaceReport)
        guard report.passed else {
            for repository in report.reports {
                for violation in repository.violations {
                    FileHandle.standardError.write(
                        Data(
                            (
                                "\(repository.repository)/\(violation.path): "
                                    + "\(violation.identifier): \(violation.message)\n"
                            ).utf8
                        )
                    )
                }
            }
            throw RepositoryPolicy.ConfigurationError(
                "repository surface policy rejected the selected scope"
            )
        }
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
            "repository-policy: scope=\(receipt.scope) examined=\(receipt.examined) "
                + "eligible=\(receipt.eligible) converged=\(receipt.converged) "
                + "enabled=\(receipt.enabled) would-enable=\(receipt.wouldEnable)"
        )
    }

    private static func write<T: Encodable>(_ value: T, to path: String?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        if let path {
            try data.write(to: URL(filePath: path), options: .atomic)
        }
        FileHandle.standardOutput.write(data)
    }

    private static func validate(_ arguments: ValidationArguments) throws {
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: URL(filePath: arguments.policy)
        )
        let report = try RepositoryPolicy.validateSurface(
            repository: arguments.repository,
            repositoryClass: arguments.repositoryClass,
            root: URL(filePath: arguments.root),
            policy: policy
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(report)
        data.append(0x0A)
        if let reportPath = arguments.report {
            try data.write(to: URL(filePath: reportPath), options: .atomic)
        }
        FileHandle.standardOutput.write(data)
        guard report.passed else {
            for violation in report.violations {
                FileHandle.standardError.write(
                    Data(
                        "\(violation.path): \(violation.identifier): \(violation.message)\n".utf8
                    )
                )
            }
            exit(1)
        }
    }

    private struct ReconcileArguments {
        var organization: String?
        var repository: String?
        var dryRun = true
        var journal: String
        var receipt: String
        var surfacePolicy: String
        var surfaceReport: String

        init(_ arguments: [String]) throws {
            let temporary = FileManager.default.temporaryDirectory
            journal = temporary.appending(path: "repository-policy-journal.jsonl").path
            receipt = temporary.appending(path: "repository-policy-receipt.json").path
            surfacePolicy = RepositoryPolicy.SurfacePolicy.instituteDefaultURL.path
            surfaceReport =
                temporary.appending(path: "repository-surface-report.json").path

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
                        throw RepositoryPolicy.ConfigurationError(
                            "--dry-run must be true or false"
                        )
                    }
                    dryRun = parsed
                case "--journal":
                    journal = value
                case "--receipt":
                    receipt = value
                case "--surface-policy":
                    surfacePolicy = value
                case "--surface-report":
                    surfaceReport = value
                default:
                    throw RepositoryPolicy.ConfigurationError("unknown argument \(name)")
                }
                index += 2
            }
        }
    }

    private struct CompactionArguments {
        let repository: String
        let issue: Int
        let revision: String
        let digest: String
        var apply = false

        init(_ arguments: [String]) throws {
            var repository: String?
            var issue: Int?
            var revision: String?
            var digest: String?
            var apply = false
            var index = 0
            while index < arguments.count {
                let name = arguments[index]
                guard index + 1 < arguments.count else {
                    throw RepositoryPolicy.ConfigurationError("missing value for \(name)")
                }
                let value = arguments[index + 1]
                switch name {
                case "--repository": repository = value
                case "--issue": issue = Int(value)
                case "--revision": revision = value
                case "--digest": digest = value
                case "--apply":
                    guard let parsed = Bool(value) else {
                        throw RepositoryPolicy.ConfigurationError("--apply must be true or false")
                    }
                    apply = parsed
                default: throw RepositoryPolicy.ConfigurationError("unknown argument \(name)")
                }
                index += 2
            }
            guard let repository, repository.split(separator: "/", omittingEmptySubsequences: false).count == 2 else {
                throw RepositoryPolicy.ConfigurationError("--repository must use owner/name form")
            }
            guard let issue, issue > 0 else {
                throw RepositoryPolicy.ConfigurationError("--issue must be a positive number")
            }
            guard let revision, !revision.isEmpty else {
                throw RepositoryPolicy.ConfigurationError("--revision is required")
            }
            guard let digest, !digest.isEmpty else {
                throw RepositoryPolicy.ConfigurationError("--digest is required")
            }
            self.repository = repository
            self.issue = issue
            self.revision = revision
            self.digest = digest
            self.apply = apply
        }
    }

    private struct ValidationArguments {
        let repository: String
        let repositoryClass: RepositoryPolicy.RepositoryClass
        let root: String
        let policy: String
        let report: String?

        init(_ arguments: [String]) throws {
            var values = [String: String]()
            var index = 0
            while index < arguments.count {
                let name = arguments[index]
                guard index + 1 < arguments.count else {
                    throw RepositoryPolicy.ConfigurationError("missing value for \(name)")
                }
                guard name.hasPrefix("--") else {
                    throw RepositoryPolicy.ConfigurationError("unknown argument \(name)")
                }
                values[name] = arguments[index + 1]
                index += 2
            }
            guard let repository = values.removeValue(forKey: "--repository") else {
                throw RepositoryPolicy.ConfigurationError("--repository is required")
            }
            guard
                let classValue = values.removeValue(forKey: "--class"),
                let repositoryClass = RepositoryPolicy.RepositoryClass(rawValue: classValue)
            else {
                throw RepositoryPolicy.ConfigurationError(
                    "--class must be package, tool, or control-plane"
                )
            }
            guard let root = values.removeValue(forKey: "--root") else {
                throw RepositoryPolicy.ConfigurationError("--root is required")
            }
            guard let policy = values.removeValue(forKey: "--policy") else {
                throw RepositoryPolicy.ConfigurationError("--policy is required")
            }
            let report = values.removeValue(forKey: "--report")
            guard values.isEmpty else {
                throw RepositoryPolicy.ConfigurationError(
                    "unknown argument \(values.keys.sorted().joined(separator: ", "))"
                )
            }
            self.repository = repository
            self.repositoryClass = repositoryClass
            self.root = root
            self.policy = policy
            self.report = report
        }
    }
}
