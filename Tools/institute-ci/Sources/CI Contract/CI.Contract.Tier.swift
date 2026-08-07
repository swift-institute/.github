extension CI.Contract {
    /// The verification tier (R1/R2 ruling 2026-07-20; 'lint' retired
    /// 2026-07-28 and refused rather than silently promoted).
    public enum Tier: String, Sendable, Equatable, CaseIterable {
        case build
        case full
    }
}
