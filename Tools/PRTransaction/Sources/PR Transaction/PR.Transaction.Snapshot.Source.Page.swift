extension PRTransaction.Snapshot.Source {
    /// One API page together with the collection's declared total count.
    public struct Page<Element: Codable & Sendable>: Codable, Sendable {
        public let total: Int
        public let values: [Element]
    }
}
