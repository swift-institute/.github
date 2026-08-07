import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// The repository a rule is asked about: its reporting name and its
    /// checked-out root.
    ///
    /// `repository` is the `owner/name` string findings cite; `root` is
    /// where the bytes are. They are separate because they diverge in
    /// every real invocation — a sweep checks out `swift-primitives/…`
    /// into a scratch path, and the fixture corpus reports
    /// `swift-institute-test/<fixture>` for a directory under `tests/`.
    ///
    /// Discovery lives here rather than in each rule so fifty validators
    /// share one definition of "the workflows of this repository",
    /// including its ordering.
    public struct Subject: Sendable, Equatable {
        public let repository: String
        public let root: String

        public init(repository: String, root: String) {
            self.repository = repository
            self.root = root
        }

        /// A path inside the subject.
        public func path(_ relative: String) -> String {
            relative.isEmpty ? root : "\(root)/\(relative)"
        }

        /// The text of a file inside the subject, or `nil` when it does
        /// not exist.
        ///
        /// Absence is `nil`, not a defect: "this repository has no
        /// `.gitignore`" is a question rules legitimately ask. A file
        /// that exists and cannot be decoded *is* a defect.
        public func text(at relative: String) throws(EnvironmentDefect) -> String? {
            let path = path(relative)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            guard let data = FileManager.default.contents(atPath: path) else {
                throw EnvironmentDefect.unreadableFile(path: path)
            }
            return String(decoding: data, as: UTF8.self)
        }

        /// Every workflow file under `.github/workflows/`, in the order
        /// the retired corpus used: `.yml` and `.yaml` gathered together
        /// and sorted by full path.
        ///
        /// The ordering is contractual. Findings are emitted in
        /// discovery order, and the differential gate compares against a
        /// Python implementation that sorted the same way.
        public func workflowPaths() throws(EnvironmentDefect) -> [String] {
            let directory = path(".github/workflows")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return [] }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                throw EnvironmentDefect.unreadableFile(path: directory)
            }
            return names
                .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
                .map { "\(directory)/\($0)" }
                .sorted()
        }

        /// Every workflow file, read.
        ///
        /// A document the reader refuses is surfaced as a `Finding`
        /// against `rule`, not as a defect — matching
        /// `load_workflow_yaml_or_emit`, which reported a parse failure
        /// as a violation of the rule being checked. Refusals and
        /// documents are returned together so a rule sees both in one
        /// pass.
        public func workflows(
            citing rule: Rule
        ) throws(EnvironmentDefect) -> (documents: [CI.Workflow.Document], refusals: [Finding]) {
            var documents: [CI.Workflow.Document] = []
            var refusals: [Finding] = []
            for path in try workflowPaths() {
                guard let data = FileManager.default.contents(atPath: path) else {
                    throw EnvironmentDefect.unreadableFile(path: path)
                }
                let name = (path as NSString).lastPathComponent
                do {
                    documents.append(
                        try CI.Workflow.Document(
                            name: name, text: String(decoding: data, as: UTF8.self)))
                } catch {
                    refusals.append(
                        Finding(
                            repository: repository, rule: rule,
                            message: "\(name): YAML parse failed: \(error.message)"))
                }
            }
            return (documents, refusals)
        }
    }
}
