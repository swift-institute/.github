import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-105]` — `continue-on-error: true` must not sit at job level on
    /// a job that delegates via `uses:`.
    ///
    /// Actions rejects that co-presence at workflow-load time with
    /// `Unexpected value 'continue-on-error'`, taking the whole call
    /// chain to `startup_failure`. The rule exists because commit
    /// `33f638b` (2026-05-05) shipped exactly that shape and broke every
    /// consumer's CI until `b5d8445` reverted it.
    ///
    /// Scope is job level and `: true` only:
    ///
    /// - Step-level `continue-on-error` is valid and out of scope.
    /// - A regular job — `runs-on:` plus `steps:` — may carry it.
    /// - A reusable workflow's *own* jobs are regular jobs; the rule is
    ///   about caller jobs.
    /// - `: false` is structurally rejected by Actions too, but the
    ///   rule's Statement scopes to `: true`, and a validator that is
    ///   broader than its Statement is a Statement amendment, not a
    ///   validator change.
    ///
    /// This is the port's proving member: the first rule carried end to
    /// end through the Swift contract and measured byte-for-byte against
    /// its retired counterpart.
    public struct ContinueOnError: Validator {
        public let rules: [Rule] = ["CI-105"]
        public let retiredScript: String? = ".github/scripts/validate-continue-on-error.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            let (documents, refusals) = try subject.workflows(citing: rule)
            var findings = refusals
            for document in documents {
                for job in document.jobs where job.isCaller {
                    guard Self.declaresTruthyContinueOnError(job) else { continue }
                    findings.append(
                        Finding(
                            repository: subject.repository, rule: rule,
                            message: Self.message(document: document.name, job: job.name)))
                }
            }
            return findings
        }

        /// Whether the job declares `continue-on-error: true` at job
        /// level.
        ///
        /// Both the boolean and the literal string `"true"` count. The
        /// string form appears because a quoted value or an expression
        /// context (`${{ env.X }}`) reaches the document as text; reading
        /// `"true"` as truthy is the conservative choice the retired
        /// validator made and the corpus encodes.
        static func declaresTruthyContinueOnError(_ job: CI.Workflow.Job) -> Bool {
            switch job.continueOnError {
            case .boolean(let value): value
            case .text(let value): value.lowercased() == "true"
            default: false
            }
        }

        static func message(document: String, job: String) -> String {
            """
            \(document): job '\(job)' has BOTH `continue-on-error: true` AND \
            `uses: <reusable>` at the same job level — per [CI-105] this \
            co-presence is forbidden. GitHub Actions parser rejects the shape \
            with `Unexpected value 'continue-on-error'`, causing \
            `startup_failure` across the entire call chain. Replace with the \
            `inputs.advisory: bool` pattern: declare `inputs.advisory` on the \
            called workflow and gate the step-level `exit` on \
            `inputs.advisory != 'true'`. See \
            `swift-institute/Research/centralized-swift-ci-and-spine-gate.md` \
            §3.5.1.
            """
        }
    }
}
