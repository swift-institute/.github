extension Repository.Policy.Caller.Parse {
    /// Which of the three admissible shapes a caller is in.
    enum Form: String {
        /// Two jobs, wrapper-hosted — the pre-TX8 fleet.
        case legacy
        /// One job, wrapper-hosted — `Render.current`.
        case current
        /// One job, universal-hosted — `Render.direct`.
        case direct
    }
}
