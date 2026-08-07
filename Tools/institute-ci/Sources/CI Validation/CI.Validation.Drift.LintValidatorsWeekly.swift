import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation.Drift {
    /// `[LINT-VALIDATORS-WEEKLY-DRIFT]` — every `scan-*` job in
    /// `lint-validators-weekly.yml` is wired into all five surfaces of
    /// that workflow's `report` job.
    ///
    /// The report job repeats its scan-leg roster five times:
    ///
    /// 1. `needs:`
    /// 2. the skipped-detection `if:` condition
    /// 3. the `RESULT_*` env block on the "Build issue body" step
    /// 4. the aggregation pair list in that step's `run:` script
    /// 5. the issue-body heredoc that same script writes
    ///
    /// Nothing checked they stayed in correspondence, and it drifted
    /// twice: once a new leg took eight hand-touched places (`9c783b0`),
    /// once a leg shipped with none of the five wired (`2cd782e`,
    /// `scan-gitignore`) and was caught by a reviewer rather than by any
    /// gate.
    ///
    /// The roster is discovered from the workflow's own `jobs:` mapping.
    /// A naming contract is enforced by construction — a job that does
    /// not follow it fails every surface, which is the right fail-closed
    /// outcome:
    ///
    /// ```
    /// scan-<slug>                  the job
    /// RESULT_<SLUG_UPPER_SNAKE>    the env var and pair-list reference
    /// validate-<slug>              the issue-body section heading
    /// ```
    ///
    /// A missing `report` job or "Build issue body" step is an
    /// `EnvironmentDefect`, not a finding: the checker could not ask its
    /// question, and reporting zero drift would be the silent no-op this
    /// rule exists to prevent.
    public struct LintValidatorsWeekly: CI.Validation.Validator {
        public typealias Finding = CI.Validation.Finding

        public let rules: [CI.Validation.Rule] = ["LINT-VALIDATORS-WEEKLY-DRIFT"]
        public let retiredScript: String? =
            ".github/scripts/check-lint-validators-weekly-parity.py"

        /// The workflow this rule reads. Fixed rather than swept: the
        /// rule is about one file's internal correspondence.
        public static let workflowPath = ".github/workflows/lint-validators-weekly.yml"

        static let reportJob = "report"
        static let buildStep = "Build issue body"

        public init() {}

        public func findings(
            in subject: CI.Validation.Subject
        ) throws(CI.Validation.EnvironmentDefect) -> [Finding] {
            guard let text = try subject.text(at: Self.workflowPath) else {
                throw .missingSupportFile(path: subject.path(Self.workflowPath))
            }
            let document: CI.Workflow.YAML.Node
            do throws(CI.Workflow.YAML.Error) {
                document = try CI.Workflow.YAML.Parser.parse(text)
            } catch {
                throw .missingSupportFile(
                    path: "\(subject.path(Self.workflowPath)) (YAML parse failed: \(error.message))")
            }
            return try Self.gaps(in: document).map { gap in
                Finding(
                    repository: subject.repository, rule: rules[0],
                    message: "\(gap.surface.rawValue): \(gap.message)")
            }
        }

        /// Every (job, surface) gap in a parsed workflow.
        ///
        /// Separate from `findings(in:)` and taking the document rather
        /// than the subject, because the positive controls perturb one
        /// surface of a synthetic document at a time. A control that had
        /// to write a file to disk to ask this question would be testing
        /// the filesystem.
        public static func gaps(
            in document: CI.Workflow.YAML.Node
        ) throws(CI.Validation.EnvironmentDefect) -> [Gap] {
            let jobs = document["jobs"]?.mapping
            let scanJobs = (jobs?.textKeys ?? []).filter { $0.hasPrefix("scan-") }.sorted()
            guard let report = jobs?[reportJob]?.mapping else {
                throw .missingSupportFile(path: "no '\(reportJob)' job in jobs:")
            }
            let needs: [String] =
                switch report["needs"] {
                case .sequence(let value): value.compactMap(\.text)
                case .text(let value): [value]
                default: []
                }
            let condition = report["if"]?.text ?? ""
            guard
                let step = report["steps"]?.sequence?
                    .first(where: { $0["name"]?.text == buildStep })?.mapping
            else {
                throw .missingSupportFile(
                    path: "no step named '\(buildStep)' in the '\(reportJob)' job")
            }
            let environment = step["env"]?.mapping
            let script = step["run"]?.text ?? ""
            let heredoc = Self.heredoc(in: script)

            var gaps: [Gap] = []
            for job in scanJobs {
                let slug = String(job.dropFirst("scan-".count))
                let result = "RESULT_" + slug.uppercased().replacingOccurrences(of: "-", with: "_")

                if !needs.contains(job) {
                    gaps.append(
                        Gap(
                            job: job, surface: .needs,
                            message: "'\(job)' is missing from the report job's needs: list"))
                }
                if !condition.contains("needs.\(job).result") {
                    gaps.append(
                        Gap(
                            job: job, surface: .condition,
                            message: "the report job's if: condition does not reference "
                                + "needs.\(job).result"))
                }
                let declared = environment?[result]
                if declared == nil {
                    gaps.append(
                        Gap(
                            job: job, surface: .environment,
                            message: "'\(buildStep)' env: block is missing \(result)"))
                } else if !(declared?.text ?? "").contains("needs.\(job).result") {
                    gaps.append(
                        Gap(
                            job: job, surface: .environment,
                            message: "\(result) does not reference needs.\(job).result (found: "
                                + "\(CI.Validation.Retired.value(declared ?? .null)))"))
                }
                let pair = "\"\(slug):$\(result)\""
                if !script.contains(pair) {
                    gaps.append(
                        Gap(
                            job: job, surface: .pairList,
                            message: "the aggregation pair list is missing \(pair)"))
                }
                let heading = "### validate-\(slug)"
                if !heredoc.contains(heading) {
                    gaps.append(
                        Gap(
                            job: job, surface: .section,
                            message: "the issue-body heredoc is missing a '\(heading)' section"))
                } else if !heredoc.contains(result) {
                    gaps.append(
                        Gap(
                            job: job, surface: .section,
                            message: "the issue-body heredoc's '\(heading)' section does not "
                                + "reference \(result)"))
                }
            }
            return gaps
        }

        /// The body of the first `<<EOF … EOF` heredoc in a `run:`
        /// script.
        ///
        /// A script with no heredoc yields the whole script, so a caller
        /// grepping for a missing section still gets a real — if less
        /// precise — finding rather than a crash. That fallback is the
        /// retired script's, kept because narrowing it would change which
        /// documents the rule fires on.
        static func heredoc(in script: String) -> String {
            let lines = script.components(separatedBy: "\n")
            guard let start = lines.firstIndex(where: { $0.contains("<<EOF") }).map({ $0 + 1 })
            else { return script }
            let body = lines[start...]
            guard
                let end = body.firstIndex(where: {
                    $0.trimmingCharacters(in: .whitespaces) == "EOF"
                })
            else { return body.joined(separator: "\n") }
            return lines[start..<end].joined(separator: "\n")
        }
    }
}

extension CI.Validation.Drift.LintValidatorsWeekly {
    /// One of the five places a scan leg must appear.
    public enum Surface: String, Sendable, CaseIterable {
        case needs
        case condition = "if-condition"
        case environment = "result-env"
        case pairList = "aggregation-pair-list"
        case section = "issue-body-section"
    }

    /// One scan job missing from one surface.
    public struct Gap: Sendable, Equatable {
        public let job: String
        public let surface: Surface
        public let message: String

        public init(job: String, surface: Surface, message: String) {
            self.job = job
            self.surface = surface
            self.message = message
        }
    }
}
