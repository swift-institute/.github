import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// `[CI-102]` — no `description:` field of a composite action may
    /// contain a `${{ ... }}` expression.
    ///
    /// Actions evaluates expressions at composite-action *load* time,
    /// including inside description fields, and rejects the whole action
    /// with HTTP 422. Descriptions are plain English; a code reference
    /// goes in backticks.
    ///
    /// Three positions carry a description and all three are scanned, in
    /// the order the retired validator read them: the action's own, then
    /// each input's, then each output's. An expression anywhere *else* —
    /// an output's `value:`, a step's `env:` — is ordinary and correct,
    /// which is what the corpus's two `edge` scenarios hold.
    public struct CompositeActionDescriptions: Validator {
        public let rules: [Rule] = ["CI-102"]
        public let retiredScript: String? =
            ".github/scripts/validate-composite-action-descriptions.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            var findings: [Finding] = []
            for name in try Self.actionDirectories(in: subject) {
                let relative = ".github/actions/\(name)/action.yml"
                guard let text = try subject.text(at: relative) else { continue }
                let document: CI.Workflow.Document
                do {
                    document = try CI.Workflow.Document(name: "action.yml", text: text)
                } catch {
                    findings.append(
                        Finding(
                            repository: subject.repository, rule: rule,
                            message: "\(name)/action.yml: YAML parse failed: \(error.message)"))
                    continue
                }
                guard let body = document.body else { continue }
                findings += Self.findings(
                    in: body, action: name, repository: subject.repository, rule: rule)
            }
            return findings
        }

        /// The names of composite actions hosted by the subject, sorted.
        ///
        /// Discovery is local to this rule because the subject *is* the
        /// action host: `CI-102` is the only member of the workflow-shape
        /// family that reads `.github/actions/` rather than
        /// `.github/workflows/`. Widening `Subject` for one consumer
        /// would put a shape in the shared contract that nothing else
        /// asks for.
        static func actionDirectories(in subject: Subject) throws(EnvironmentDefect) -> [String] {
            let directory = subject.path(".github/actions")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return [] }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                throw EnvironmentDefect.unreadableFile(path: directory)
            }
            return names.filter {
                FileManager.default.fileExists(atPath: "\(directory)/\($0)/action.yml")
            }.sorted()
        }

        static func findings(
            in body: CI.Workflow.YAML.Mapping, action: String, repository: String, rule: Rule
        ) -> [Finding] {
            var findings: [Finding] = []
            func scan(_ node: CI.Workflow.YAML.Node?, at location: String) {
                guard let text = node?.text, text.containsExpression else { return }
                findings.append(
                    Finding(
                        repository: repository, rule: rule,
                        message: message(action: action, location: location)))
            }
            scan(body["description"], at: "top-level")
            for section in ["inputs", "outputs"] {
                guard let entries = body[section]?.mapping else { continue }
                for entry in entries.entries {
                    guard let name = entry.key.text, let specification = entry.value.mapping
                    else { continue }
                    scan(specification["description"], at: "\(section).\(name)")
                }
            }
            return findings
        }

        static func message(action: String, location: String) -> String {
            """
            \(action)/action.yml: \(location) description contains \
            `${{ ... }}` expression — per [CI-102] composite-action \
            description fields are parsed at composite-load time and reject \
            all expression syntax (HTTP 422). Rewrite as plain English with \
            backtick code-refs (e.g., `` `PRIVATE_REPO_TOKEN` secret from the \
            caller ``).
            """
        }
    }
}

extension String {
    /// Whether the text opens an Actions expression anywhere.
    ///
    /// The opening delimiter alone is the predicate the rule states — an
    /// unclosed `${{` is rejected by the same parser for the same reason,
    /// so requiring a matching `}}` would narrow the rule below its
    /// Statement.
    fileprivate var containsExpression: Bool { contains("${{") }
}
