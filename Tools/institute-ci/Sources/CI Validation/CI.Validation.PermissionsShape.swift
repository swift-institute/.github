import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-090]` workflow-level `permissions:` per trigger shape, and
    /// `[CI-097]` the deny-all-on-reusable case.
    ///
    /// One detection point serves both, because both rules turn on the
    /// same two facts: whether the workflow is callable, and what its
    /// top-level `permissions:` key holds.
    ///
    /// Actions intersects a reusable's top-level grant with the calling
    /// job's, so a top-level block on a reusable can only ever *narrow*
    /// what the caller asked for — invisibly, at the callee. A reusable
    /// therefore omits the block and lets per-job grants carry the floor.
    /// A standalone workflow has no caller to intersect with, so the
    /// block is the only floor there is and its absence inherits the
    /// repository default.
    ///
    /// `[CI-097]` is the limit case of that intersection: `permissions:
    /// {}` on a reusable caps every caller at zero and produces
    /// `startup_failure` at each one — the M2 incident. It is a subset of
    /// `[CI-090]` and preferred over it when both apply, because the
    /// specific diagnostic names the actual failure.
    ///
    /// A combined workflow — `workflow_call` alongside standalone
    /// triggers — is judged as a reusable. The intersection rule applies
    /// to it whenever it is called, and the shape that is safe under
    /// every trigger is the reusable one.
    public struct PermissionsShape: Validator {
        public let rules: [Rule] = ["CI-090", "CI-097"]
        public let retiredScript: String? = ".github/scripts/validate-permissions-shape.py"

        /// Triggers under which a workflow runs on its own account.
        static let standaloneTriggers = ["schedule", "workflow_dispatch", "push", "pull_request"]

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            // Parse refusals cite CI-090, the general rule of the pair,
            // as the retired validator did.
            let (documents, refusals) = try subject.workflows(citing: rules[0])
            var findings = refusals
            for document in documents {
                guard let triggers = document.triggers, let body = document.body else { continue }
                let isCallable = triggers["workflow_call"] != nil
                let isStandalone = Self.standaloneTriggers.contains { triggers[$0] != nil }
                // Absent, present-and-empty, and present-and-populated are
                // three distinct states, and the rule separates all three.
                let declared = body["permissions"]
                if isCallable {
                    guard declared != nil else { continue }
                    let denyAll = declared == .mapping(.init([])) || declared == .null
                    findings.append(
                        Finding(
                            repository: subject.repository,
                            rule: denyAll ? "CI-097" : "CI-090",
                            message: denyAll
                                ? Self.denyAllMessage(document: document.name)
                                : Self.reusableMessage(document: document.name)))
                } else if isStandalone, declared == nil {
                    findings.append(
                        Finding(
                            repository: subject.repository, rule: "CI-090",
                            message: Self.standaloneMessage(document: document.name)))
                }
            }
            return findings
        }

        static func denyAllMessage(document: String) -> String {
            """
            \(document): workflow has `on: workflow_call` and declares top-level \
            `permissions: {}` — per [CI-097] this deny-all is forbidden on \
            reusables. The workflow_call permissions intersection rule caps the \
            effective grant at zero, producing `startup_failure` at every caller \
            (the M2 incident shape). Remove the top-level block; per-job grants \
            provide the floor.
            """
        }

        static func reusableMessage(document: String) -> String {
            """
            \(document): workflow has `on: workflow_call` and declares top-level \
            `permissions:` — per [CI-090] reusables MUST omit top-level \
            permissions. The workflow_call intersection rule caps the caller's \
            grant at min(top-level, caller-job). Move the grants to per-job \
            `permissions:` blocks instead.
            """
        }

        static func standaloneMessage(document: String) -> String {
            """
            \(document): standalone workflow (no `workflow_call:` trigger) MUST \
            declare top-level `permissions:` per [CI-090] — typically \
            `permissions: {}` as a deny-all floor with per-job grants overriding. \
            Without the floor, the workflow inherits GitHub's repo-default \
            permissions (often broader than needed).
            """
        }
    }
}
