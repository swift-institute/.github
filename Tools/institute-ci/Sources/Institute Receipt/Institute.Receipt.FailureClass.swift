extension Institute.Receipt {
    /// Typed refusal classes for receipt validation — the Swift owner of
    /// the §13.3 runtime-mode finding codes, plus the R35/K-21
    /// strengthenings (empty identity family, zero mandatory jobs).
    public enum FailureClass: Sendable, Equatable {
        case stageNotTerminal(field: String)
        case nullTerminalField(field: String)
        case mandatoryJobNotSuccess(job: Int, conclusion: String)
        case jobsPaginationIncomplete(total: Int, present: Int)
        case shortSha(field: String, value: String)
        case emptySubject
        case emptyIdentityFamily(field: String)
        case zeroMandatoryJobs
        case localPath(subject: String)
    }
}
