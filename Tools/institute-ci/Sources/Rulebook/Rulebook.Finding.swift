extension Rulebook {
    /// One thing the canon says that is not so.
    ///
    /// `key` is what the ratchet matches on and is deliberately coarser
    /// than the message: it names the file and the identifier or path,
    /// but not the line. A baselined finding that moves down its file is
    /// the same finding, and a ratchet keyed on line numbers would go red
    /// on every edit above it and teach its readers to re-baseline
    /// reflexively.
    ///
    /// `message` carries the line, because that is what a person needs.
    public struct Finding: Sendable, Equatable {
        public let check: Check
        public let key: String
        public let message: String

        public init(check: Check, key: String, message: String) {
            self.check = check
            self.key = key
            self.message = message
        }

        /// The baseline line for this finding: `<check> <key>`.
        public var baselineEntry: String { "\(check.rawValue) \(key)" }
    }
}
