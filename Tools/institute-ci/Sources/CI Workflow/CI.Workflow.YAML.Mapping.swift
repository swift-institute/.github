import CI_Contract

extension CI.Workflow.YAML {
    /// An **order-preserving** YAML mapping.
    ///
    /// Order is part of the contract, not a convenience. Findings are
    /// emitted in document order and the differential gate compares
    /// sorted TSV against a Python implementation whose `dict` preserves
    /// insertion order; a `Dictionary` here would make emission order
    /// non-deterministic across runs.
    ///
    /// Keys are stored as resolved `Node`s rather than `String`s so the
    /// YAML 1.1 quirks survive lookup. `on:` is a boolean key; asking for
    /// `"on"` correctly misses, and `CI.Workflow.Document` performs the
    /// same two-step recovery the Python contract documented.
    public struct Mapping: Sendable, Equatable {
        public typealias Entry = (key: Node, value: Node)

        public let entries: [Entry]

        public init(_ entries: [Entry]) {
            self.entries = entries
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.entries.count == rhs.entries.count else { return false }
            for (left, right) in zip(lhs.entries, rhs.entries) {
                guard left.key == right.key, left.value == right.value else { return false }
            }
            return true
        }

        /// The value for a resolved key node, in document order.
        public subscript(node key: Node) -> Node? {
            entries.first { $0.key == key }?.value
        }

        /// The value for a string key. A key that resolved to a boolean —
        /// `on`, `yes`, `off` — is deliberately **not** reachable this
        /// way; see `Document.triggers`.
        public subscript(key: String) -> Node? {
            self[node: .text(key)]
        }

        /// The mapping's keys as text, skipping keys that did not resolve
        /// to strings.
        public var textKeys: [String] {
            entries.compactMap(\.key.text)
        }
    }
}
