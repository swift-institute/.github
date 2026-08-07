import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-103]` — a job's `runs-on:` and `container:` must not
    /// reference workflow-level `env:`.
    ///
    /// Actions resolves both fields *before* workflow-level `env:` is
    /// bound, so `${{ env.X }}` there is not a wrong value — it is a
    /// parse-time HTTP 422 that takes the whole workflow down at load.
    /// The rule exists because `ecf36e6` and `91dd8db` (2026-05-05)
    /// shipped `container: swift:${{ env.SWIFT_VERSION }}` and broke two
    /// cron orchestrators until `e9b468e` reverted to a literal.
    ///
    /// Only the `env` context is in scope. `inputs.*`, `vars.*`,
    /// `matrix.*`, `github.*` and `secrets.*` are all legitimately
    /// available in these fields, and a validator that flagged them would
    /// be flagging the recommended fix.
    ///
    /// Both failure modes carry into the list and dict spellings: a
    /// `runs-on: [...]` element and a dict-form `container.image:` bind at
    /// the same time as their scalar shorthands.
    public struct EnvironmentContext: Validator {
        public let rules: [Rule] = ["CI-103"]
        public let retiredScript: String? = ".github/scripts/validate-env-context.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            let (documents, refusals) = try subject.workflows(citing: rule)
            var findings = refusals
            for document in documents {
                for job in document.jobs {
                    findings += Self.findings(
                        in: job, of: document, repository: subject.repository, rule: rule)
                }
            }
            return findings
        }

        /// One job's two fields, in the order the retired validator read
        /// them: `runs-on:` first, then `container:`. A job can violate
        /// both and is reported twice.
        static func findings(
            in job: CI.Workflow.Job, of document: CI.Workflow.Document,
            repository: String, rule: Rule
        ) -> [Finding] {
            var findings: [Finding] = []
            if let runsOn = job.runsOn, runsOn != .null, referencesEnvironment(runsOn) {
                findings.append(
                    Finding(
                        repository: repository, rule: rule,
                        message: runsOnMessage(document: document.name, job: job.name)))
            }
            guard let container = job.body["container"], container != .null else {
                return findings
            }
            switch container {
            case .text:
                if referencesEnvironment(container) {
                    findings.append(
                        Finding(
                            repository: repository, rule: rule,
                            message: containerMessage(document: document.name, job: job.name)))
                }
            case .mapping(let mapping):
                if let image = mapping["image"], referencesEnvironment(image) {
                    findings.append(
                        Finding(
                            repository: repository, rule: rule,
                            message: imageMessage(document: document.name, job: job.name)))
                }
            default:
                break
            }
            return findings
        }

        /// Whether the node's text carries a `${{ env.X }}` reference.
        ///
        /// Text and sequences only. A boolean or an integer cannot carry
        /// an expression, and stringifying one to search it would be the
        /// `value is True or value == "true"` conflation the contract
        /// exists to prevent.
        static func referencesEnvironment(_ node: CI.Workflow.YAML.Node) -> Bool {
            switch node {
            case .text(let value): value.referencesEnvironmentContext
            case .sequence(let elements): elements.contains(where: referencesEnvironment)
            default: false
            }
        }

        static func runsOnMessage(document: String, job: String) -> String {
            """
            \(document): job '\(job)' has `runs-on:` referencing \
            `${{ env.X }}` — per [CI-103] workflow-level `env:` is NOT \
            available in `runs-on:` (Actions resolves this field before env: \
            binds; produces parse-time HTTP 422). Use `inputs.<name>` \
            (workflow_call), `vars.<name>` (org/repo level), or literal \
            hardcode instead.
            """
        }

        static func containerMessage(document: String, job: String) -> String {
            """
            \(document): job '\(job)' has `container:` referencing \
            `${{ env.X }}` — per [CI-103] workflow-level `env:` is \
            NOT available in `container:` (same context-availability \
            rule as `runs-on:`; produces parse-time HTTP 422). Use \
            `inputs.<name>`, `vars.<name>`, or literal hardcode.
            """
        }

        static func imageMessage(document: String, job: String) -> String {
            """
            \(document): job '\(job)' has `container.image:` \
            referencing `${{ env.X }}` — per [CI-103] workflow-\
            level `env:` is NOT available in `container:` (dict-form \
            `image:` is bound at the same time as the string-form \
            shorthand; same HTTP 422 trigger).
            """
        }
    }
}

extension String {
    /// `${{`, optional whitespace, `env.`, at least one word character —
    /// the Actions expression spelling of an `env` context read.
    ///
    /// Scanned rather than pattern-matched because the shape is three
    /// literal tokens with one whitespace run between them, and a
    /// hand-written scanner is the honest expression of that. Whitespace
    /// and word membership follow the retired regex's classes so the
    /// corpus's spacing variants resolve identically.
    fileprivate var referencesEnvironmentContext: Bool {
        let characters = Array(self)
        let opening = Array("${{")
        let keyword = Array("env.")
        var index = 0
        while index + opening.count <= characters.count {
            guard Array(characters[index..<(index + opening.count)]) == opening else {
                index += 1
                continue
            }
            var cursor = index + opening.count
            while cursor < characters.count, characters[cursor].isExpressionWhitespace {
                cursor += 1
            }
            if cursor + keyword.count <= characters.count,
               Array(characters[cursor..<(cursor + keyword.count)]) == keyword,
               cursor + keyword.count < characters.count,
               characters[cursor + keyword.count].isExpressionWord
            {
                return true
            }
            index += 1
        }
        return false
    }
}

extension Character {
    /// Python's `\s`: space, tab, newline, carriage return, form feed,
    /// vertical tab.
    fileprivate var isExpressionWhitespace: Bool {
        self == " " || self == "\t" || self == "\n" || self == "\r" || self == "\u{0C}"
            || self == "\u{0B}"
    }

    /// Python's `\w`: a letter, a digit, or an underscore.
    fileprivate var isExpressionWord: Bool {
        isLetter || isNumber || self == "_"
    }
}
