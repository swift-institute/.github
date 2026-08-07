import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// `[GH-REPO-METADATA]` — JSON-Schema validation of a repository's
    /// `.github/metadata.yaml` against `metadata-schema.json`.
    ///
    /// The Swift owner of `validate-github-metadata.py` (Wave 2b
    /// finalization, Decision 6). The subject is a directory carrying the
    /// fetched `.github/metadata.yaml`; the schema is a **support file**
    /// of this control plane, named by the caller or found by walking up
    /// from the working directory — the same resolution posture as
    /// `Gitignore`'s canon.
    ///
    /// Rule identifiers are derived from the validation-error path
    /// exactly as the retired script derived them: `topics` →
    /// `GH-REPO-021-or-022`, `description` → `GH-REPO-011`, `homepage` →
    /// `GH-REPO-030-or-031`, `readme` → `README-family`, anything else →
    /// `GH-REPO-021`. The pre-schema shape checks keep their sentinel
    /// rules: `metadata-missing`, `metadata-malformed`, `metadata-shape`.
    ///
    /// One deliberate difference from the retired script: an unreadable
    /// or malformed **schema** was a `schema-load-failed` finding there;
    /// under this contract an unanswerable question is the exit-2 class,
    /// so it throws `EnvironmentDefect.missingSupportFile`. A YAML parse
    /// failure of the *subject* stays a finding, but its message is this
    /// reader's, not PyYAML's.
    public struct GitHubMetadata: Validator {
        /// Every rule the retired script could emit.
        public let rules: [Rule] = [
            "GH-REPO-011", "GH-REPO-021", "GH-REPO-021-or-022",
            "GH-REPO-030-or-031", "README-family",
            "metadata-malformed", "metadata-missing", "metadata-shape",
        ]
        public let retiredScript: String? = ".github/scripts/validate-github-metadata.py"

        /// The schema's path within the control-plane checkout.
        public static let schemaPath = "metadata-schema.json"

        /// Where the schema lives. `nil` means *find it*: the working
        /// directory and each of its ancestors are searched for
        /// `metadata-schema.json`.
        public let schema: String?

        public init(schema: String? = nil) {
            self.schema = schema
        }

        /// The metadata file's location within the subject.
        public static let metadataPath = ".github/metadata.yaml"

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let schemaFile = schema ?? Self.resolvedSchemaPath ?? Self.schemaPath
            guard let schemaData = FileManager.default.contents(atPath: schemaFile),
                let schemaNode = Schema.JSON.parse(String(decoding: schemaData, as: UTF8.self))
            else {
                throw .missingSupportFile(path: schemaFile)
            }

            let path = subject.path(Self.metadataPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                return [
                    Finding(
                        repository: subject.repository, rule: "metadata-missing",
                        message: "\(path): file not found")
                ]
            }
            guard let data = FileManager.default.contents(atPath: path) else {
                throw .unreadableFile(path: path)
            }

            let document: CI.Workflow.YAML.Node
            do throws(CI.Workflow.YAML.Error) {
                document = try CI.Workflow.YAML.Parser.parse(
                    String(decoding: data, as: UTF8.self))
            } catch {
                return [
                    Finding(
                        repository: subject.repository, rule: "metadata-malformed",
                        message: "\(path): YAML parse error — \(error.message)")
                ]
            }

            // An empty file is allowed at present, matching the script.
            if case .null = document { return [] }
            guard case .mapping = document else {
                return [
                    Finding(
                        repository: subject.repository, rule: "metadata-shape",
                        message: "\(path): top-level value must be a mapping; "
                            + "got \(Self.pythonTypeName(of: document))")
                ]
            }

            let issues = try Schema(schemaNode, source: schemaFile)
                .issues(in: document)
                .enumerated()
                .sorted {
                    Schema.Issue.ordered($0.element.path, $1.element.path)
                        ?? ($0.offset < $1.offset)
                }
                .map(\.element)
            return issues.map { issue in
                Finding(
                    repository: subject.repository,
                    rule: Self.rule(for: issue.path),
                    message: "\(issue.location): "
                        + String(issue.message.unicodeScalars.prefix(200)))
            }
        }

        /// The rule an error path cites, in the retired script's
        /// precedence order.
        static func rule(for path: [Schema.Issue.Element]) -> Rule {
            let keys = path.map(\.description)
            if keys.contains("topics") { return "GH-REPO-021-or-022" }
            if keys.contains("description") { return "GH-REPO-011" }
            if keys.contains("homepage") { return "GH-REPO-030-or-031" }
            if keys.contains("readme") { return "README-family" }
            return "GH-REPO-021"
        }

        /// `type(data).__name__` for the shapes `safe_load` can return.
        static func pythonTypeName(of node: CI.Workflow.YAML.Node) -> String {
            switch node {
            case .null: "NoneType"
            case .boolean: "bool"
            case .integer: "int"
            case .number: "float"
            case .text: "str"
            case .sequence: "list"
            case .mapping: "dict"
            }
        }

        /// `schemaPath` found by walking up from the working directory,
        /// or `nil` when no ancestor carries it.
        static var resolvedSchemaPath: String? {
            var directory = FileManager.default.currentDirectoryPath
            while !directory.isEmpty, directory != "/" {
                let candidate = "\(directory)/\(schemaPath)"
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
                    !isDirectory.boolValue
                {
                    return candidate
                }
                directory = (directory as NSString).deletingLastPathComponent
            }
            return nil
        }
    }
}
