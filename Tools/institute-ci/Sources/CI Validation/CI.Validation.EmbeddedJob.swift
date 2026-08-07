import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-021]` — a `swift-ci.yml` that declares an `embedded` job must
    /// give that job `continue-on-error: true`.
    ///
    /// The embedded build runs against the Swift `main` nightly
    /// toolchain, whose instability is expected. An advisory posture
    /// absorbs toolchain noise without gating consumer CI. The rule
    /// sunsets by amendment when the embedded gate moves to a stable
    /// toolchain.
    ///
    /// Scope is one canonical file. A repository that does not host
    /// `swift-ci.yml`, or whose `swift-ci.yml` has no `embedded` job, is
    /// out of scope and the validator is silent — silence here means
    /// "not asked", which is why the corpus keeps both shapes as `pass`
    /// and `edge` rather than folding them together.
    ///
    /// Only the *boolean* `true` satisfies the rule. The string `"true"`
    /// does not, and the corpus's `embedded-coe-false` scenario is what
    /// holds that line. This is deliberately narrower than `CI-105`,
    /// which reads a quoted `"true"` as truthy: `CI-105` asks whether
    /// Actions will reject the shape, so a value that *might* resolve
    /// truthy is enough; `CI-021` asks whether the advisory posture is
    /// actually declared, so nothing but the declaration counts.
    public struct EmbeddedJob: Validator {
        public let rules: [Rule] = ["CI-021"]
        public let retiredScript: String? = ".github/scripts/validate-embedded-job.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            guard let text = try subject.text(at: ".github/workflows/swift-ci.yml") else {
                return []
            }
            let document: CI.Workflow.Document
            do {
                document = try CI.Workflow.Document(name: "swift-ci.yml", text: text)
            } catch {
                return [
                    Finding(
                        repository: subject.repository, rule: rule,
                        message: "swift-ci.yml: YAML parse failed: \(error.message)")
                ]
            }
            guard let embedded = document.jobs.first(where: { $0.name == "embedded" }) else {
                return []
            }
            guard embedded.continueOnError?.boolean == true else {
                return [
                    Finding(repository: subject.repository, rule: rule, message: Self.message)
                ]
            }
            return []
        }

        static let message = """
            swift-ci.yml: job 'embedded' MUST set `continue-on-error: true` per \
            [CI-021] — the embedded build runs against Swift main nightly \
            toolchain whose instability is expected; advisory posture absorbs \
            toolchain-noise without gating consumer CI. Sunsets via skill \
            amendment when the embedded gate moves to a stable toolchain \
            (until then, the gate stays advisory).
            """
    }
}
