extension Fleet.Inventory {
    /// The portable per-repository fleet census: every row carries the
    /// exact head and caller blob identity, every zero rides a positive
    /// control (A-07 / v1-per-root shape).
    public struct Census: Sendable, Equatable {
        public struct Row: Sendable, Equatable {
            public let repository: String
            public let headSha: String
            public let callerBlobSha: String
            public let classification: String

            public init(
                repository: String, headSha: String,
                callerBlobSha: String, classification: String
            ) {
                self.repository = repository
                self.headSha = headSha
                self.callerBlobSha = callerBlobSha
                self.classification = classification
            }
        }

        public struct PositiveControl: Sendable, Equatable {
            public let name: String
            public let fired: Bool

            public init(name: String, fired: Bool) {
                self.name = name
                self.fired = fired
            }
        }

        public enum Error: Swift.Error, Equatable {
            case zeroWithoutPositiveControl
            case duplicateRepository(String)
        }

        public let rows: [Row]
        public let positiveControls: [PositiveControl]

        /// A census refuses construction when it asserts an empty result
        /// with no fired positive control, or lists a repository twice —
        /// a zero from the wrong root is not evidence.
        public init(
            rows: [Row], positiveControls: [PositiveControl]
        ) throws(Error) {
            if rows.isEmpty && !positiveControls.contains(where: \.fired) {
                throw .zeroWithoutPositiveControl
            }
            var seen: Set<String> = []
            for row in rows {
                guard seen.insert(row.repository).inserted else {
                    throw .duplicateRepository(row.repository)
                }
            }
            self.rows = rows
            self.positiveControls = positiveControls
        }
    }
}
