extension Repository.Policy.Metadata {
    /// The only way drafting or reading metadata refuses.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The target is not in `owner/name` form.
        case malformedRepository(String)
    }
}
