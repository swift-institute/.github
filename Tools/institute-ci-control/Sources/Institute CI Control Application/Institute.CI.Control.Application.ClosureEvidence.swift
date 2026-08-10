import Closure_Evidence
import Foundation

extension Institute.CI.Control.Application {
    /// The credentialed edge of the closure-evidence audit
    /// (swift-institute/.github#512): enumerate issues closed as
    /// completed since a lookback window, resolve what their comments
    /// cite, and hand the recorded facts to `Closure.Evidence.Verdict`.
    ///
    /// Everything credentialed is here, and nothing else is: the
    /// citation parsing and the verdict are `Closure Evidence`'s and are
    /// proved there without a token. All GitHub reads and writes go
    /// through `gh` argument vectors ([CI-081]: no shell, no
    /// caller-supplied command).
    ///
    /// Mutation posture (recorded on #512): a violating issue in a
    /// writable repository receives one marker-deduplicated flag
    /// comment; an issue whose cited fix run is observed *failed* is
    /// additionally reopened with the evidence — the ratified
    /// reopen-with-evidence rule. A denied mutation (the token is the
    /// swift-institute installation; other orgs' repositories are
    /// readable but not writable) degrades to a report line, never a
    /// crash.
    public enum ClosureEvidence {
        /// The marker that makes the flag comment idempotent across runs.
        public static let marker = "<!-- closure-evidence-audit -->"

        public enum Error: Swift.Error {
            case missingToken
            case organizationUnsearchable(String)
        }

        public struct Finding {
            public let issue: String
            public let title: String
            public let verdict: Closure.Evidence.Verdict
            public var flagged = false
            public var reopened = false
            public var mutationDenied = false
        }

        public struct Outcome {
            public var compliant = 0
            public var violations: [Finding] = []
        }

        public static func audit(
            organizations: [String],
            sinceDays: Int,
            token: String,
            mutate: Bool,
            reportPath: String?,
            summaryPath: String?
        ) throws(Error) -> Outcome {
            if token.isEmpty { throw .missingToken }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let since = formatter.string(
                from: Date().addingTimeInterval(-Double(sinceDays) * 86_400))

            var outcome = Outcome()
            for organization in organizations {
                let issues = try search(organization: organization, since: since, token: token)
                for issue in issues {
                    var finding = judge(issue, token: token)
                    if case .violation(let reason) = finding.verdict {
                        if mutate {
                            apply(&finding, issue: issue, reason: reason, token: token)
                        }
                        outcome.violations.append(finding)
                    } else {
                        outcome.compliant += 1
                    }
                }
            }
            write(outcome, since: since, reportPath: reportPath, summaryPath: summaryPath)
            return outcome
        }

        // MARK: - The credentialed reads

        struct Issue {
            let owner: String
            let repository: String
            let number: Int
            let url: String
            let title: String
        }

        static func search(
            organization: String, since: String, token: String
        ) throws(Error) -> [Issue] {
            let completion = Audit.run(
                ["gh", "api", "-X", "GET", "search/issues", "--paginate",
                 "-f", "q=org:\(organization) is:issue is:closed reason:completed closed:>=\(since)",
                 "-f", "per_page=100",
                 "--jq", ".items[] | [.html_url, .title] | @json"],
                environment: ["GH_TOKEN": token])
            guard completion.status == 0 else {
                throw .organizationUnsearchable(organization)
            }
            return completion.standardOutput.split(separator: "\n").compactMap { line in
                guard let pair = decode([String].self, String(line)), pair.count == 2,
                      let coordinate = coordinate(of: pair[0])
                else { return nil }
                return Issue(
                    owner: coordinate.owner, repository: coordinate.repository,
                    number: coordinate.number, url: pair[0], title: pair[1])
            }
        }

        /// `https://github.com/<owner>/<repo>/issues/<n>` → its parts.
        static func coordinate(of url: String) -> (owner: String, repository: String, number: Int)? {
            let prefix = "https://github.com/"
            guard url.hasPrefix(prefix) else { return nil }
            let parts = url.dropFirst(prefix.count).split(separator: "/")
            guard parts.count == 4, parts[2] == "issues", let number = Int(parts[3])
            else { return nil }
            return (String(parts[0]), String(parts[1]), number)
        }

        static func judge(_ issue: Issue, token: String) -> Finding {
            let completion = Audit.run(
                ["gh", "api", "--paginate",
                 "repos/\(issue.owner)/\(issue.repository)/issues/\(issue.number)/comments",
                 "--jq", ".[].body | @json"],
                environment: ["GH_TOKEN": token])
            var runReferences: [Closure.Evidence.Citation.RunReference] = []
            var commits: [String] = []
            var alreadyFlagged = false
            if completion.status == 0 {
                for line in completion.standardOutput.split(separator: "\n") {
                    guard let body = decode(String.self, String(line)) else { continue }
                    if body.contains(marker) { alreadyFlagged = true }
                    let citation = Closure.Evidence.Citation(of: body)
                    for reference in citation.runs where !runReferences.contains(reference) {
                        runReferences.append(reference)
                    }
                    for commit in citation.commits where !commits.contains(commit) {
                        commits.append(commit)
                    }
                }
            }

            var runs: [Closure.Evidence.Run] = []
            var unresolved: [Closure.Evidence.Citation.RunReference] = []
            for reference in runReferences {
                if let run = resolve(reference, commits: commits, token: token) {
                    runs.append(run)
                } else {
                    unresolved.append(reference)
                }
            }
            var finding = Finding(
                issue: issue.url, title: issue.title,
                verdict: .of(runs: runs, unresolved: unresolved, commitCited: !commits.isEmpty))
            if alreadyFlagged { finding.flagged = true }
            return finding
        }

        /// Resolve one cited run against GitHub's own run object — the
        /// run's `conclusion` field, never a lane's claim about it.
        static func resolve(
            _ reference: Closure.Evidence.Citation.RunReference,
            commits: [String], token: String
        ) -> Closure.Evidence.Run? {
            let completion = Audit.run(
                ["gh", "api",
                 "repos/\(reference.owner)/\(reference.repository)/actions/runs/\(reference.identifier)",
                 "--jq", "[.conclusion // \"null\", .head_sha] | @json"],
                environment: ["GH_TOKEN": token])
            guard completion.status == 0,
                  let pair = decode(
                    [String].self,
                    completion.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
                  pair.count == 2
            else { return nil }
            var orderings: [String: Closure.Evidence.Run.Ordering] = [:]
            for commit in commits {
                orderings[commit] = ordering(
                    of: pair[1], against: commit, in: reference, token: token)
            }
            return Closure.Evidence.Run(
                reference: reference,
                conclusion: .init(name: pair[0]),
                orderings: orderings)
        }

        static func ordering(
            of head: String, against commit: String,
            in reference: Closure.Evidence.Citation.RunReference, token: String
        ) -> Closure.Evidence.Run.Ordering {
            let completion = Audit.run(
                ["gh", "api",
                 "repos/\(reference.owner)/\(reference.repository)/compare/\(commit)...\(head)",
                 "--jq", ".status"],
                environment: ["GH_TOKEN": token])
            guard completion.status == 0 else { return .unknown }
            switch completion.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "identical", "ahead": return .atOrAfter
            case "behind": return .before
            case "diverged": return .unrelated
            default: return .unknown
            }
        }

        // MARK: - The ratified mutations

        static func apply(
            _ finding: inout Finding, issue: Issue,
            reason: Closure.Evidence.Verdict.Reason, token: String
        ) {
            if !finding.flagged {
                let commented = Audit.run(
                    ["gh", "api", "-X", "POST",
                     "repos/\(issue.owner)/\(issue.repository)/issues/\(issue.number)/comments",
                     "-f", "body=\(marker)\n\(flag(reason))"],
                    environment: ["GH_TOKEN": token])
                if commented.status == 0 {
                    finding.flagged = true
                } else {
                    finding.mutationDenied = true
                }
            }
            // Reopen only the observed-broken class: a cited fix run
            // that concluded failure. Missing-citation classes stay
            // flag-and-report per #512.
            if case .citedRunFailed = reason {
                let reopened = Audit.run(
                    ["gh", "api", "-X", "PATCH",
                     "repos/\(issue.owner)/\(issue.repository)/issues/\(issue.number)",
                     "-f", "state=open"],
                    environment: ["GH_TOKEN": token])
                if reopened.status == 0 {
                    finding.reopened = true
                } else {
                    finding.mutationDenied = true
                }
            }
        }

        static func flag(_ reason: Closure.Evidence.Verdict.Reason) -> String {
            let rule = """
                Per the ratified closure-evidence rule \
                (https://github.com/swift-institute/.github/issues/512), a completed \
                closure must cite an Actions run URL whose own `conclusion` is \
                `success` at-or-after the fix commit. A commit SHA alone is not \
                closure evidence, and a cancelled run is not evidence.
                """
            return "Closure-evidence audit: \(describe(reason)).\n\n\(rule)"
        }

        static func describe(_ reason: Closure.Evidence.Verdict.Reason) -> String {
            switch reason {
            case .noRunCited(true):
                return "closed as completed citing a commit SHA but no run URL"
            case .noRunCited(false):
                return "closed as completed with no run URL cited"
            case .citedRunFailed(let reference):
                return "the cited run \(reference.url) concluded `failure`"
            case .citedRunNotEvidence(let reference, let conclusion):
                return "the cited run \(reference.url) concluded `\(conclusion)`, which is not evidence"
            case .runPredatesCitedCommit(let reference, let commit):
                return "the cited run \(reference.url) predates the cited fix commit `\(commit)`"
            case .runUnresolvable(let reference):
                return "the cited run \(reference.url) could not be resolved"
            }
        }

        // MARK: - Reporting

        static func write(
            _ outcome: Outcome, since: String, reportPath: String?, summaryPath: String?
        ) {
            var lines = [
                "Closure-evidence audit of issues closed as completed since \(since) (UTC).",
                "",
                "Compliant closures: \(outcome.compliant). Violations: \(outcome.violations.count).",
                "",
            ]
            for finding in outcome.violations {
                var line = "- \(finding.issue) — "
                if case .violation(let reason) = finding.verdict { line += describe(reason) }
                if finding.reopened { line += " (reopened)" }
                if finding.mutationDenied { line += " (mutation denied; repository not writable by this installation)" }
                lines.append(line)
            }
            if outcome.violations.isEmpty { lines.append("Fleet clean.") }
            let report = lines.joined(separator: "\n") + "\n"
            if let reportPath {
                try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            }
            if let summaryPath, let handle = FileHandle(forWritingAtPath: summaryPath) {
                handle.seekToEndOfFile()
                handle.write(Data(report.utf8))
                try? handle.close()
            }
        }

        static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
            try? JSONDecoder().decode(type, from: Data(json.utf8))
        }
    }
}
