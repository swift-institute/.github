import Foundation
import Repository_Policy

extension Approval {
    struct Arguments {
        let targets: String
        let source: String
        let dryRun: Bool

        init(_ arguments: [String]) throws {
            var targets: String?
            var source: String?
            var dryRun: Bool?
            var index = 0
            while index < arguments.count {
                guard index + 1 < arguments.count else {
                    throw RepositoryPolicy.ConfigurationError(
                        "converge-approval-callers requires a value after \(arguments[index])"
                    )
                }
                let value = arguments[index + 1]
                switch arguments[index] {
                case "--targets-file": targets = value
                case "--source": source = value
                case "--dry-run":
                    switch value {
                    case "true": dryRun = true
                    case "false": dryRun = false
                    default:
                        throw RepositoryPolicy.ConfigurationError(
                            "converge-approval-callers --dry-run must be true or false"
                        )
                    }
                default:
                    throw RepositoryPolicy.ConfigurationError(
                        "unknown converge-approval-callers argument: \(arguments[index])"
                    )
                }
                index += 2
            }
            guard let targets, let source, let dryRun else {
                throw RepositoryPolicy.ConfigurationError(
                    "converge-approval-callers requires --targets-file, --source, and --dry-run"
                )
            }
            self.targets = targets
            self.source = source
            self.dryRun = dryRun
        }
    }
}
