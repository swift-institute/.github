extension Repository.Policy.Approval.Caller {
    public struct Receipt: Codable, Sendable, Equatable {
        public let examined: Int
        public let proposed: Int
        public let opened: Int
        public let dryRun: Bool

        public init(examined: Int, proposed: Int, opened: Int, dryRun: Bool) {
            self.examined = examined
            self.proposed = proposed
            self.opened = opened
            self.dryRun = dryRun
        }
    }
}
