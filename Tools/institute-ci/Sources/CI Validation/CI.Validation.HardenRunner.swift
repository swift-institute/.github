import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-080]` — every in-scope job's first step is a SHA-pinned
    /// `step-security/harden-runner`.
    ///
    /// First, not merely present: the action constrains egress for the
    /// steps that follow it, so a step ahead of it runs unconstrained,
    /// and that is exactly the position a supply-chain step would take.
    /// SHA-pinned, not tag-pinned, for the same reason the action exists
    /// — a mutable tag hands the integrity guarantee back to whoever can
    /// move the tag.
    ///
    /// Two carve-outs, both structural rather than discretionary:
    ///
    /// - A caller job — `uses:` at job level, no `steps:` — runs nothing
    ///   itself; the called workflow's own jobs each install their own.
    /// - The conclusion aggregator (`ci-ok`) runs `jq` over
    ///   `needs.*.result` with no network egress to constrain.
    ///
    /// A job with neither `steps:` nor a job-level `uses:` is a shape
    /// Actions itself rejects; the rule passes over it rather than
    /// reporting a security finding about a workflow that cannot load.
    public struct HardenRunner: Validator {
        public let rules: [Rule] = ["CI-080"]
        public let retiredScript: String? = ".github/scripts/validate-harden-runner.py"

        static let action = "step-security/harden-runner@"

        /// Jobs whose whole body is a conclusion aggregation.
        static let aggregators: Set<String> = ["ci-ok"]

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            let (documents, refusals) = try subject.workflows(citing: rule)
            var findings = refusals
            for document in documents {
                for job in document.jobs {
                    guard !Self.isRouting(job), !Self.aggregators.contains(job.name),
                          let first = Self.firstStep(job)
                    else { continue }
                    let uses = (first["uses"] ?? .text("")).pythonString
                    let quoted = CI.Workflow.YAML.Node.repr(uses)
                    let message: String? =
                        if !uses.hasPrefix(Self.action) {
                            Self.absentMessage(
                                document: document.name, job: job.name, uses: quoted)
                        } else if !Self.isPinnedToDigest(uses) {
                            Self.unpinnedMessage(
                                document: document.name, job: job.name, uses: quoted)
                        } else {
                            nil
                        }
                    guard let message else { continue }
                    findings.append(
                        Finding(repository: subject.repository, rule: rule, message: message))
                }
            }
            return findings
        }

        /// A `workflow_call` routing job: `uses:` at job level and no
        /// `steps:`. Key presence, not a resolved value — a job that
        /// declares both keys is not routing, whatever either holds.
        static func isRouting(_ job: CI.Workflow.Job) -> Bool {
            job.body["uses"] != nil && job.body["steps"] == nil
        }

        /// The job's first step, when it has one that is a mapping.
        ///
        /// Read off the raw sequence rather than the filtered `steps`
        /// view: a malformed leading entry means the *first* step is not
        /// inspectable, which the retired validator treated as an odd
        /// shape to skip — not as licence to inspect the second one.
        static func firstStep(_ job: CI.Workflow.Job) -> CI.Workflow.YAML.Mapping? {
            job.body["steps"]?.sequence?.first?.mapping
        }

        /// `step-security/harden-runner@<40 lower-case hex>`.
        static func isPinnedToDigest(_ uses: String) -> Bool {
            let digest = uses.dropFirst(Self.action.count)
            return digest.count == 40
                && digest.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
        }

        static func absentMessage(document: String, job: String, uses: String) -> String {
            """
            \(document): job \(CI.Workflow.YAML.Node.repr(job)) first step is not \
            `step-security/harden-runner@*` per [CI-080] — security floor \
            requires harden-runner as the first step on every in-scope job. \
            first step uses=\(uses)
            """
        }

        static func unpinnedMessage(document: String, job: String, uses: String) -> String {
            """
            \(document): job \(CI.Workflow.YAML.Node.repr(job)) harden-runner not \
            SHA-pinned per [CI-080] — security action MUST pin to \
            `@<40-char-sha>`, not a major-tag like `@v2.19.1`. got uses=\(uses)
            """
        }
    }
}
