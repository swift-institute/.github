extension Rulebook {
    /// One skill directory: a `SKILL.md` hub and the companions beside
    /// it.
    ///
    /// A hub **routes by topic**; it does not restate every identifier
    /// its companions define. That is why the hub-index check asks only
    /// that each companion be *named* from the hub, and asks separately
    /// that a file's own registry claims be traceable in that file's own
    /// body. Requiring the hub to enumerate everything would push the
    /// corpus back toward the duplication the review found.
    public struct Skill: Sendable {
        /// The aliased directory — `institute:architecture`.
        public let alias: String
        public let directory: String
        public let members: [Document]

        public init(alias: String, directory: String, members: [Document]) {
            self.alias = alias
            self.directory = directory
            self.members = members
        }

        public var hub: Document? { members.first { $0.name == "SKILL.md" } }
        public var companions: [Document] { members.filter { $0.name != "SKILL.md" } }
    }
}
