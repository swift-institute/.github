import CI_Contract

extension CI.Validation {
    /// The machine could not be asked the question.
    ///
    /// This is the `exit 2` class, and the distinction it carries is the
    /// most important one in the contract: **a defect is not a finding.**
    /// A missing parser, an unreadable tree, a subject root that is not a
    /// directory — none of these mean the repository is clean, and none
    /// mean it is dirty. The control plane must fail loudly rather than
    /// report zero findings, which is exactly what four inert gates did
    /// before this distinction was drawn.
    ///
    /// Every `Validator` operation throws this and only this, so a rule
    /// implementation cannot accidentally widen its error surface into
    /// the finding channel.
    public enum EnvironmentDefect: Swift.Error, Sendable, Equatable {
        /// The subject's root is absent or is not a directory.
        case unreadableSubject(root: String)

        /// A file the validator had already discovered could not be read.
        case unreadableFile(path: String)

        /// A support file the validator requires — a manifest, a schema —
        /// is missing. Distinct from a *subject* file being absent, which
        /// is ordinarily a finding.
        case missingSupportFile(path: String)

        public var message: String {
            switch self {
            case .unreadableSubject(let root):
                "subject root is not a readable directory: \(root)"
            case .unreadableFile(let path):
                "file could not be read: \(path)"
            case .missingSupportFile(let path):
                "required support file is missing: \(path)"
            }
        }

        /// The process exit code this defect maps to. Named rather than
        /// literal so no front end re-derives it.
        public static var exitCode: Int32 { 2 }
    }
}
