extension Repository.Policy.Eligibility {
    /// One repository whose CI is bespoke by ruling, with the ruling that
    /// made it so.
    ///
    /// `reason` is a required stored property, not a comment beside the
    /// coordinate, so that an entry cannot be added without naming what
    /// authorized it. It carries the durable coordinate of the ruling; a
    /// bare display name would not survive a rename.
    public struct Exception: Sendable, Equatable {
        /// The full `owner/name` coordinate.
        public let repository: String
        public let reason: String

        public init(repository: String, reason: String) {
            self.repository = repository
            self.reason = reason
        }
    }
}
