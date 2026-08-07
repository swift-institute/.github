import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[GH-REPO-074]`, `[CI-030]`, `[CI-059]`, and
    /// `INTEGRATED-DOCS-ADMISSION` — a per-package `ci.yml` is a thin
    /// caller, pinned at `@main`, carrying the credential shape its
    /// hosting organization requires.
    ///
    /// - **`[GH-REPO-074]`** — no inline `runs-on:` or `steps:` in any
    ///   job, at least one job delegating via `uses:`, and no standalone
    ///   `swift-format.yml` / `swiftlint.yml` (the format and lint legs
    ///   were absorbed into the universal matrix on 2026-05-10).
    /// - **`[CI-030]`** — an intra-Institute reusable ref pins to `@main`
    ///   while the surface is pre-`v1`. The discriminator is the
    ///   `.github/.github/workflows/` double infix, unique to
    ///   org-`.github` reusables; a third-party ref
    ///   (`actions/checkout@v6`) has a different shape and is exempt
    ///   under `[CI-107]`.
    /// - **`[CI-059]`** — a same-org caller carries `secrets: inherit`
    ///   and nothing else; a **sub-org** caller carries the inverse,
    ///   because its hop into the parent layer wrapper is cross-org,
    ///   where `inherit` silently delivers no org secrets (`[CI-109]`).
    ///   That inversion is the reason the rule needs the hosting org at
    ///   all.
    /// - **`INTEGRATED-DOCS-ADMISSION`** — TX10 deleted the temporary
    ///   `integrated-docs` input, so a caller still sending it fails at
    ///   run time on an undeclared input. A live breakage, not a style
    ///   nit; absence is the terminal shape and is not a finding.
    ///
    /// Reusables are exempt from all four at file level: a workflow
    /// declaring `on: workflow_call:` *is* the reusable, and these rules
    /// constrain callers.
    ///
    /// **Why this reads lines rather than the typed document.** Every
    /// predicate here is line-anchored by design, and deliberately so:
    /// the rules must still produce diagnostics on a workflow the parser
    /// refuses, because an unparseable `ci.yml` is a broken caller and
    /// reporting nothing would be the worst possible answer. The typed
    /// reader is used for the one predicate that genuinely needs
    /// parseability — the diagnostic-precedence proof below — where
    /// failing closed is correct.
    ///
    /// It also does not consume `Repository.Policy.Caller.Parse`, and
    /// that is not an oversight. `Parse` is `Render`'s inverse and fails
    /// closed on anything the renderer cannot emit; this validator's
    /// subjects are arbitrary repository workflows, most of which are
    /// exactly the non-canonical shapes `Parse` refuses. Routing them
    /// through `Parse` would collapse every distinct diagnostic into one
    /// "unknown customization", which is the opposite of what the rule
    /// is for.
    public struct ThinCallers: Validator {
        public let rules: [Rule] = [
            "CI-030", "CI-059", "GH-REPO-074", "INTEGRATED-DOCS-ADMISSION",
        ]
        public let retiredScript: String? = ".github/scripts/validate-thin-callers.py"

        public init() {}

        /// The thirteen per-authority sub-orgs whose `[CI-059]`
        /// obligation inverts. Derived from `SubOrgWrappers`, which is
        /// authoritative for the set — two spellings of the same thirteen
        /// organizations is precisely the drift that produced the
        /// validators manifest.
        static var subOrganizations: Set<String> { SubOrgWrappers.subOrganizations }

        /// The credential set a cross-org caller forwards. Principal-ruled
        /// **closed** on #92: a block missing a name fires, and a block
        /// carrying any name beyond it fires as wider than the set.
        /// Widening this is a ruling, not an edit.
        public static let crossOrganizationSecrets: [String] = [
            "PRIVATE_REPO_TOKEN",
            "SWIFT_INSTITUTE_BOT_APP_CLIENT_ID",
            "SWIFT_INSTITUTE_BOT_APP_ID",
            "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
        ]

        /// The rule identifier an exempted `[CI-059]` finding is reported
        /// under. The aggregation layer counts exact `CI-059` rows only,
        /// so an exempted finding stays visible without counting.
        static let exemptRule: Rule = "CI-059-EXEMPT"

        /// One `[CI-059]` predicate. An exemption admits exactly one of
        /// these in exactly one file; every other class in the same file
        /// still fires.
        enum FindingClass: String {
            case sameOrganizationExplicit = "same-org-explicit"
            case sameOrganizationOmitted = "same-org-omitted"
            case crossOrganizationInherit = "cross-org-inherit"
            case crossOrganizationMissingNames = "cross-org-missing-names"
            case crossOrganizationExtraNames = "cross-org-extra-names"
            case crossOrganizationOmitted = "cross-org-omitted"
        }

        /// The typed `[CI-059]` exemptions, keyed by repository and
        /// workflow path (#92: "exceptions exist only as typed whitelist
        /// entries with exact repository + path scope"). Adding a
        /// production entry requires a principal ruling.
        ///
        /// The single entry is fixture-scoped. `swift-institute-test` is
        /// the harness's reporting owner and no production sweep ever
        /// passes it, so the entry can admit nothing outside the corpus —
        /// it exists so the exemption path has a failing control: an
        /// admitted shape, plus a near-miss that must still fire.
        static let exemptions: [Exemption] = [
            Exemption(
                repository: "swift-institute-test/swift-exempt-explicit-caller",
                path: ".github/workflows/ci.yml",
                admits: .sameOrganizationExplicit,
                ruling: "fixture-scoped mechanism control; not a production ruling")
        ]

        struct Exemption {
            let repository: String
            let path: String
            let admits: FindingClass
            let ruling: String
        }

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            // `[GH-REPO-074]` scopes to per-package repositories. No root
            // manifest, no obligation.
            guard try subject.text(at: "Package.swift") != nil else { return [] }
            var findings: [Finding] = []
            if let text = try subject.text(at: ".github/workflows/ci.yml") {
                findings += try Self.findings(in: text, subject: subject)
            }
            findings += try Self.standaloneWorkflowFindings(in: subject)
            return findings
        }

        static func findings(
            in text: String, subject: Subject
        ) throws(EnvironmentDefect) -> [Finding] {
            // File-level carve-out for every rule here: a workflow that
            // declares `workflow_call:` *is* a reusable. Tool-host
            // packages ([GH-REPO-077]) host action refs on purpose.
            guard !Line.all(text).contains(where: { $0.declaresWorkflowCall }) else { return [] }

            let repository = subject.repository
            var findings: [Finding] = []
            let supersedes = supersedesInlineDiagnostics(text)

            if Line.all(text).contains(where: \.isInlineRunsOn), !supersedes {
                findings.append(
                    Finding(repository: repository, rule: "GH-REPO-074", message: Message.inlineRunsOn))
            }
            if Line.all(text).contains(where: \.isInlineSteps), !supersedes {
                findings.append(
                    Finding(repository: repository, rule: "GH-REPO-074", message: Message.inlineSteps))
            }
            if !Line.all(text).contains(where: \.isJobUses) {
                findings.append(
                    Finding(repository: repository, rule: "GH-REPO-074", message: Message.noReusable))
            }
            findings += pinFindings(in: text, repository: repository)
            findings += secretFindings(
                in: text, repository: repository,
                organization: try hostingOrganization(of: subject))
            findings += integratedDocsFindings(in: text, repository: repository)
            return findings
        }

        /// The organization whose `[CI-059]` branch applies.
        ///
        /// Production reads the repository coordinate's org component. A
        /// `.fixture-sub-org-owner` marker at the subject root overrides
        /// it: the harness reports every scenario as
        /// `swift-institute-test/<name>`, so the sub-org branch would
        /// otherwise be unreachable from the corpus. An empty marker
        /// names `swift-ietf`.
        static func hostingOrganization(
            of subject: Subject
        ) throws(EnvironmentDefect) -> String {
            if let marker = try subject.text(at: ".fixture-sub-org-owner") {
                var named = Substring(marker)
                while let first = named.first, first.isWhitespace { named = named.dropFirst() }
                while let last = named.last, last.isWhitespace { named = named.dropLast() }
                return named.isEmpty ? "swift-ietf" : String(named)
            }
            return String(subject.repository.prefix { $0 != "/" })
        }

        // MARK: - [GH-REPO-074]

        static func standaloneWorkflowFindings(
            in subject: Subject
        ) throws(EnvironmentDefect) -> [Finding] {
            var findings: [Finding] = []
            for name in ["swift-format.yml", "swiftlint.yml"] {
                guard try subject.text(at: ".github/workflows/\(name)") != nil else { continue }
                findings.append(
                    Finding(
                        repository: subject.repository, rule: "GH-REPO-074",
                        message: Message.standaloneWorkflow(name)))
            }
            return findings
        }

        /// Whether the missing-reusable finding is the root the two
        /// inline findings would only restate.
        ///
        /// This is diagnostic factoring, not a narrowing of
        /// `[GH-REPO-074]`: correcting the root — replacing every inline
        /// job with a reusable caller — necessarily removes those same
        /// jobs' `runs-on:` and `steps:`, so reporting all three describes
        /// one repair three times. Suppression requires *proof*: one
        /// canonical `jobs:` mapping, the typed reader agreeing on the
        /// same job set, no job-level `uses:` anywhere, every job inline,
        /// and every broad match accounted for as a direct key of a
        /// parsed job. Mixed, partial, non-canonical, and unparseable
        /// shapes keep all three findings. Prevalence and repository
        /// identity are not inputs.
        static func supersedesInlineDiagnostics(_ text: String) -> Bool {
            let jobs = self.jobs(in: text)
            guard hasOneCanonicalJobsMapping(text, jobs: jobs) else { return false }
            guard readerAgrees(text, jobs: jobs) else { return false }
            guard !Line.all(text).contains(where: \.isJobUses) else { return false }
            guard !jobs.contains(where: { $0.lines.contains(where: \.isDirectJobUses) }) else {
                return false
            }
            guard jobs.allSatisfy({ job in
                job.lines.contains(where: \.isDirectJobRunsOn)
                    && job.lines.contains(where: \.isDirectJobSteps)
            }) else { return false }

            let directRunsOn = jobs.reduce(0) { $0 + $1.lines.count(where: \.isDirectJobRunsOn) }
            let directSteps = jobs.reduce(0) { $0 + $1.lines.count(where: \.isDirectJobSteps) }
            let allRunsOn = Line.all(text).count(where: \.isInlineRunsOn)
            let allSteps = Line.all(text).count(where: \.isInlineSteps)
            return directRunsOn + directSteps > 0
                && directRunsOn == allRunsOn && directSteps == allSteps
        }

        /// Whether the line walk accounted for exactly one canonical
        /// `jobs:` mapping. Any alias, inline mapping, malformed
        /// boundary, non-canonical indent, duplicate `jobs:` key, or
        /// content before the first job fails the proof closed.
        static func hasOneCanonicalJobsMapping(_ text: String, jobs: [Job]) -> Bool {
            let lines = Line.all(text)
            let starts = lines.indices.filter { lines[$0].isJobsKey }
            guard starts.count == 1, !jobs.isEmpty else { return false }

            var parsed = 0
            var inJob = false
            for line in lines[lines.index(after: starts[0])...] {
                if line.isTopLevelKey { break }
                if line.isBlankOrComment { continue }
                guard line.indent != 2 else {
                    guard line.isJobNameLine else { return false }
                    parsed += 1
                    inJob = true
                    continue
                }
                if line.indent < 4 || !inJob { return false }
            }
            return parsed == jobs.count
        }

        /// Whether the typed reader confirms the same job mapping.
        ///
        /// Textual indentation alone cannot establish parseability. This
        /// second gate fails closed on a refused document, a non-mapping
        /// root or job, a duplicate job name, or any disagreement between
        /// the line walk and the reader about the job set.
        static func readerAgrees(_ text: String, jobs: [Job]) -> Bool {
            let document: CI.Workflow.Document
            do throws(CI.Workflow.YAML.Error) {
                document = try CI.Workflow.Document(name: "ci.yml", text: text)
            } catch {
                // A document the reader refuses proves nothing, and this
                // is the one predicate here that must fail closed: the
                // suppression it gates would otherwise be granted on an
                // unverified walk.
                return false
            }
            guard let mapping = document.body?["jobs"]?.mapping else { return false }
            let read = mapping.entries.compactMap { entry -> String? in
                guard entry.value.mapping != nil else { return nil }
                return entry.key.text
            }
            return read.count == mapping.entries.count && read == jobs.map(\.name)
        }

        // MARK: - [CI-030]

        static func pinFindings(in text: String, repository: String) -> [Finding] {
            Line.all(text).compactMap { line in
                guard let reference = line.intraInstituteReference, reference.ref != "main"
                else { return nil }
                return Finding(
                    repository: repository, rule: "CI-030",
                    message: Message.unpinnedReference(reference))
            }
        }

        // MARK: - [CI-059]

        static func secretFindings(
            in text: String, repository: String, organization: String
        ) -> [Finding] {
            let crossOrganization = subOrganizations.contains(organization)
            return jobs(in: text).flatMap { job -> [Finding] in
                guard job.lines.contains(where: { $0.intraInstituteReference != nil }) else {
                    return []  // this job invokes no intra-Institute reusable
                }
                return crossOrganization
                    ? crossOrganizationFindings(job, repository: repository)
                    : sameOrganizationFindings(job, repository: repository)
            }
        }

        static func sameOrganizationFindings(_ job: Job, repository: String) -> [Finding] {
            if job.lines.contains(where: \.isSecretsInherit) { return [] }
            let explicit = job.lines.contains { $0.isSecretsBlock || $0.isSecretsInlineMap }
            return [
                classified(
                    explicit ? .sameOrganizationExplicit : .sameOrganizationOmitted,
                    repository: repository,
                    message: explicit
                        ? Message.sameOrganizationExplicit(job: job.name)
                        : Message.sameOrganizationOmitted(job: job.name))
            ]
        }

        static func crossOrganizationFindings(_ job: Job, repository: String) -> [Finding] {
            if job.lines.contains(where: \.isSecretsInherit) {
                return [
                    classified(
                        .crossOrganizationInherit, repository: repository,
                        message: Message.crossOrganizationInherit(job: job.name))
                ]
            }
            guard job.lines.contains(where: { $0.isSecretsBlock || $0.isSecretsInlineMap }) else {
                return [
                    classified(
                        .crossOrganizationOmitted, repository: repository,
                        message: Message.crossOrganizationOmitted(job: job.name))
                ]
            }
            var findings: [Finding] = []
            let missing = crossOrganizationSecrets.filter { name in
                !job.lines.contains { $0.forwards(name) }
            }
            if !missing.isEmpty {
                findings.append(
                    classified(
                        .crossOrganizationMissingNames, repository: repository,
                        message: Message.crossOrganizationMissing(job: job.name, names: missing)))
            }
            let extra = job.forwardedSecretNames.filter { !crossOrganizationSecrets.contains($0) }
            if !extra.isEmpty {
                findings.append(
                    classified(
                        .crossOrganizationExtraNames, repository: repository,
                        message: Message.crossOrganizationExtra(job: job.name, names: extra)))
            }
            return findings
        }

        /// A `[CI-059]` finding, routed through the typed-exemption gate.
        ///
        /// An exemption never suppresses a different class in the same
        /// file, and never suppresses the row itself — it only changes the
        /// identifier it is reported under, so the finding stays legible
        /// while the aggregation layer stops counting it.
        static func classified(
            _ findingClass: FindingClass, repository: String, message: String
        ) -> Finding {
            guard let exemption = exemptions.first(where: {
                $0.repository == repository && $0.path == ".github/workflows/ci.yml"
                    && $0.admits == findingClass
            }) else {
                return Finding(
                    repository: repository, rule: "CI-059",
                    message: "[\(findingClass.rawValue)] \(message)")
            }
            return Finding(
                repository: repository, rule: exemptRule,
                message: "[\(findingClass.rawValue)] admitted by typed exemption "
                    + "(\(exemption.ruling)): \(message)")
        }

        // MARK: - INTEGRATED-DOCS-ADMISSION

        static func integratedDocsFindings(in text: String, repository: String) -> [Finding] {
            jobs(in: text).compactMap { job in
                guard job.name == "ci",
                    let value = job.withBlockValue("integrated-docs")
                else { return nil }
                return Finding(
                    repository: repository, rule: "INTEGRATED-DOCS-ADMISSION",
                    message: Message.integratedDocs(value))
            }
        }
    }
}
