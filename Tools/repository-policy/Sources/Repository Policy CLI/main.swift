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
            } else if CommandLine.arguments.dropFirst().first == "ruleset" {
                try ruleset(RulesetArguments(Array(CommandLine.arguments.dropFirst(2))))
            } else if CommandLine.arguments.dropFirst().first == "render-caller" {
                try renderCaller(Array(CommandLine.arguments.dropFirst(2)))
            } else if CommandLine.arguments.dropFirst().first == "parse-caller" {
                try parseCaller(Array(CommandLine.arguments.dropFirst(2)))
            } else if CommandLine.arguments.dropFirst().first == "draft-metadata" {
                try draftMetadata(Array(CommandLine.arguments.dropFirst(2)))
            } else if CommandLine.arguments.dropFirst().first == "census" {
                try census(Array(CommandLine.arguments.dropFirst(2)))
            } else if CommandLine.arguments.dropFirst().first == "capability-records" {
                try capabilityRecords(Array(CommandLine.arguments.dropFirst(2)))
            } else if CommandLine.arguments.dropFirst().first == "ruleset-convergence" {
                try rulesetConvergence(
                    RulesetConvergenceArguments(Array(CommandLine.arguments.dropFirst(2)))
                )
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
        let plan = try await RepositoryPolicy.GitHubClient(token: token, baseURL: baseURL)
            .compactIssue(
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
        let client = RepositoryPolicy.GitHubClient(token: token, baseURL: baseURL)

        // Surface-policy validation and private-vulnerability-reporting
        // reconciliation are unrelated concerns over the same scope and must
        // each fail on their own merits — the same rule that already governs
        // this reusable workflow's top-level `sync` vs `surfaces` job split
        // (see the note above `jobs:` in sync-metadata.yml, swift-institute/
        // .github#160). That split did not reach one level deeper: inside
        // this single step, an org-scope surface-policy violation in ONE
        // repository unconditionally threw before `RepositoryPolicy.run`
        // ever started, silently skipping vulnerability-reporting
        // reconciliation for every OTHER, fully-conforming repository in
        // that org on every scheduled sweep (swift-institute/.github#278,
        // diagnosed via #222: the step's name and its actual predicate had
        // diverged). Run both predicates unconditionally, report both, and
        // fail closed at the end if either failed — never let one predicate
        // suppress the other's execution.
        let surfaceReport = try await RepositoryPolicy.validateSurfaces(
            client: client,
            scope: scope,
            policy: policy
        )
        try write(surfaceReport, to: arguments.surfaceReport)
        if !surfaceReport.passed {
            for repository in surfaceReport.reports {
                for violation in repository.violations {
                    FileHandle.standardError.write(
                        Data(
                            ("\(repository.repository)/\(violation.path): "
                                + "\(violation.identifier): \(violation.message)\n").utf8
                        )
                    )
                }
            }
        }

        let receipt = try await RepositoryPolicy.run(
            client: client,
            configuration: .init(
                scope: scope,
                dryRun: arguments.dryRun,
                journal: URL(filePath: arguments.journal),
                receipt: URL(filePath: arguments.receipt)
            )
        )
        // `excluded` names why an examined repository (including an
        // explicitly named single one) did not reconcile, so a divergence
        // is legible from the step output alone (swift-institute/.github#160).
        let excludedDescription =
            receipt.excluded.isEmpty
            ? "none"
            : receipt.excluded.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
        print(
            "repository-policy: scope=\(receipt.scope) examined=\(receipt.examined) "
                + "eligible=\(receipt.eligible) excluded=\(excludedDescription) "
                + "converged=\(receipt.converged) enabled=\(receipt.enabled) "
                + "would-enable=\(receipt.wouldEnable)"
        )

        guard surfaceReport.passed else {
            throw RepositoryPolicy.ConfigurationError(
                "repository surface policy rejected the selected scope "
                    + "(vulnerability-reporting reconciliation above still ran to completion)"
            )
        }
    }

    private static func ruleset(_ arguments: RulesetArguments) throws {
        let url = URL(filePath: arguments.policy)
        let payload: Data
        // TX5 (swift-institute/.github#276): the migration-window public
        // compatibility variant and its `--compatibility` flag are retired —
        // the terminal contract is the only public package payload.
        switch (arguments.repositoryClass, arguments.visibility) {
        case (.package, .public):
            payload = try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        case (.package, .private):
            payload = try RepositoryPolicy.Ruleset.protectedMainPrivatePayload(from: url)
        case (.controlPlane, _):
            payload = try RepositoryPolicy.Ruleset.protectedMainControlPayload(from: url)
        case (.tool, _):
            throw RepositoryPolicy.ConfigurationError(
                "ruleset --class must be package or control-plane"
            )
        }
        FileHandle.standardOutput.write(payload)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// The heal-existing-vs-skip-absent decision for one repository
    /// (swift-institute/.github#204). Pure and network-free: the caller
    /// resolves whether an Institute ruleset currently exists and passes
    /// that in, this only decides the mechanical action.
    private static func rulesetConvergence(_ arguments: RulesetConvergenceArguments) throws {
        let decision = RepositoryPolicy.Ruleset.decideConvergence(
            rulesetExists: arguments.rulesetExists,
            mode: arguments.mode
        )
        try write(decision, to: nil)
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
            guard let repository,
                repository.split(separator: "/", omittingEmptySubsequences: false).count == 2
            else {
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

    private struct RulesetArguments {
        /// Repository visibility, read live from GitHub
        /// (`GET /repos/{full_name}` → `.visibility`) by the caller — this
        /// type never has a default case and the CLI never infers it, so an
        /// unreadable visibility must fail closed one level up (the caller
        /// shell/workflow step, `UNMEASURED`, never silently defaulted to
        /// either value; swift-institute/.github#276 Task 3-01).
        enum Visibility: String {
            case `public`
            case `private`
        }

        let policy: String
        let repositoryClass: RepositoryPolicy.RepositoryClass
        let visibility: Visibility

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
            guard let policy = values.removeValue(forKey: "--policy") else {
                throw RepositoryPolicy.ConfigurationError("ruleset requires --policy <path>")
            }
            // Defaults to `package` so any caller predating the control-plane
            // variant (swift-institute/.github#200) keeps its prior behavior
            // unchanged.
            let classValue =
                values.removeValue(forKey: "--class")
                ?? RepositoryPolicy.RepositoryClass.package.rawValue
            guard
                let repositoryClass = RepositoryPolicy.RepositoryClass(rawValue: classValue),
                repositoryClass == .package || repositoryClass == .controlPlane
            else {
                throw RepositoryPolicy.ConfigurationError(
                    "--class must be package or control-plane"
                )
            }
            // Defaults to `public` so every caller predating Task 3-01 (the
            // control-plane class, and every existing public-package
            // invocation) keeps its prior behavior unchanged. A
            // control-plane target ignores this value entirely — it selects
            // no required-check context either way.
            let visibilityValue = values.removeValue(forKey: "--visibility") ?? Visibility.public.rawValue
            guard let visibility = Visibility(rawValue: visibilityValue) else {
                throw RepositoryPolicy.ConfigurationError(
                    "--visibility must be public or private"
                )
            }
            guard values.isEmpty else {
                throw RepositoryPolicy.ConfigurationError(
                    "unknown argument \(values.keys.sorted().joined(separator: ", "))"
                )
            }
            self.policy = policy
            self.repositoryClass = repositoryClass
            self.visibility = visibility
        }
    }

    private struct RulesetConvergenceArguments {
        let mode: RepositoryPolicy.Ruleset.SweepMode
        let rulesetExists: Bool

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
            guard
                let modeValue = values.removeValue(forKey: "--mode"),
                let mode = RepositoryPolicy.Ruleset.SweepMode(rawValue: modeValue)
            else {
                throw RepositoryPolicy.ConfigurationError(
                    "ruleset-convergence requires --mode scheduled-heal or explicit-apply"
                )
            }
            guard
                let existingValue = values.removeValue(forKey: "--existing-ruleset"),
                let existing = Bool(existingValue)
            else {
                throw RepositoryPolicy.ConfigurationError(
                    "ruleset-convergence requires --existing-ruleset true or false"
                )
            }
            guard values.isEmpty else {
                throw RepositoryPolicy.ConfigurationError(
                    "unknown argument \(values.keys.sorted().joined(separator: ", "))"
                )
            }
            self.mode = mode
            self.rulesetExists = existing
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
