import CI_Contract

extension CI.Validation {
    /// One rule violation, in the shape `validate-base.yml` aggregates.
    ///
    /// The TSV encoding is the wire format the whole control plane reads,
    /// so it lives on the value rather than at each call site. Tabs and
    /// newlines are flattened to spaces in the message — and *only* in
    /// the message — because the aggregation step splits on tabs and
    /// would otherwise read a wrapped sentence as extra columns.
    public struct Finding: Sendable, Equatable, Comparable {
        public let repository: String
        public let rule: Rule
        public let message: String

        public init(repository: String, rule: Rule, message: String) {
            self.repository = repository
            self.rule = rule
            self.message = message
        }

        /// `repository<TAB>rule<TAB>message`, one line, no terminator.
        public var tsv: String {
            var flattened = ""
            flattened.reserveCapacity(message.count)
            for character in message {
                flattened.append(character == "\t" || character == "\n" ? " " : character)
            }
            return "\(repository)\t\(rule.rawValue)\t\(flattened)"
        }

        /// Sorted order is TSV-lexicographic, so a differential run can
        /// compare two implementations without depending on either one's
        /// emission order.
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.tsv < rhs.tsv }
    }
}
