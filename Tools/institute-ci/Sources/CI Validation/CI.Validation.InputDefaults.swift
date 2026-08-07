import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-058]` — a reusable that declares `enable-private-repos` must
    /// default it to `true`.
    ///
    /// The canonical consumer depends on private intra-Institute
    /// siblings, so the default that needs no argument is the one that
    /// enables the private-repo configure-git step. A public-only
    /// consumer opts out explicitly, which is the direction that fails
    /// loudly rather than silently.
    ///
    /// A workflow that does not declare the input is out of scope; the
    /// rule is about the declaration's default, not about which
    /// workflows must declare it.
    ///
    /// The default must be the **boolean** `true`. The retired validator
    /// compared by identity against Python's `True` singleton, so the
    /// string `"true"` was already a violation, and the typed node keeps
    /// that distinction rather than reconstructing it.
    public struct InputDefaults: Validator {
        public let rules: [Rule] = ["CI-058"]
        public let retiredScript: String? = ".github/scripts/validate-input-defaults.py"

        /// The one input this rule governs.
        static let input = "enable-private-repos"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            let (documents, refusals) = try subject.workflows(citing: rule)
            var findings = refusals
            for document in documents {
                guard
                    let specification = document.triggers?["workflow_call"]?["inputs"]?[Self.input]?
                        .mapping
                else { continue }
                let declared = specification["default"]
                guard declared != .boolean(true) else { continue }
                findings.append(
                    Finding(
                        repository: subject.repository, rule: rule,
                        message: Self.message(
                            document: document.name,
                            declared: declared?.pythonRepr ?? "None")))
            }
            return findings
        }

        static func message(document: String, declared: String) -> String {
            """
            \(document): `on.workflow_call.inputs.\(Self.input).default` must be \
            `true` per [CI-058] — the canonical case (most consumers depend on \
            private intra-Institute siblings) wants the default to enable the \
            private-repo configure-git step. Public-only consumers MAY pass \
            `with: { \(Self.input): false }` explicitly to opt out. Got \
            default=\(declared).
            """
        }
    }
}
