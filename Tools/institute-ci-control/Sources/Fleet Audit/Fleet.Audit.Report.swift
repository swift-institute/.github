import Foundation

extension Fleet.Audit {
    /// One package's audit result, as the audit reports it.
    ///
    /// The audit writes a JSON document; the sweep reads counters out of
    /// it at a configured dotted path. The document keeps whatever else
    /// the audit chose to record — the sweep neither needs nor inspects
    /// it — so this type models exactly the part the contract owns: a
    /// name, and a set of named counters.
    public struct Report: Sendable, Equatable {
        public let package: String
        public let counters: [String: Int]

        public init(package: String, counters: [String: Int]) {
            self.package = package
            self.counters = counters
        }

        /// The audit's own JSON rendering, byte-for-byte the shape
        /// `audit-mechanical-hygiene.py` wrote: `package`, `dir`, and a
        /// `totals` object.
        public func json(directory: String) -> String {
            let totals = counters.keys.sorted()
                .map { "    \"\($0)\": \(counters[$0]!)" }
                .joined(separator: ",\n")
            return """
                {
                  "package": "\(package)",
                  "dir": "\(directory)",
                  "totals": {
                \(totals)
                  }
                }
                """
        }

        /// Read the counters a configuration names out of an audit's
        /// JSON document.
        ///
        /// Unreadable, malformed and structurally surprising documents
        /// all yield zeros rather than refusing, matching the retired
        /// runner: a package whose audit could not run must not stop the
        /// sweep over the rest of the org. The zeros are visible in the
        /// per-org counts artefact, which is where that condition is
        /// meant to be read.
        public static func counters(
            inJSON text: String, at totalsPath: String, keys: [String]
        ) -> [String: Int] {
            var totals: [String: Any] = [:]
            if let data = text.data(using: .utf8),
               let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                totals = navigate(object, path: totalsPath)
            }
            var counters: [String: Int] = [:]
            for key in keys { counters[key] = counter(totals[key]) }
            return counters
        }

        /// Navigate a dotted path into a nested object. An empty path is
        /// the object itself; a missing or non-object member is empty.
        static func navigate(_ object: [String: Any], path: String) -> [String: Any] {
            if path.isEmpty { return object }
            var current = object
            for component in path.split(separator: ".").map(String.init) {
                guard let next = current[component] as? [String: Any] else { return [:] }
                current = next
            }
            return current
        }

        /// A counter value, however the audit spelled it. Absent, null,
        /// empty and unparseable all read as zero — the retired runner's
        /// `int(totals.get(k, 0) or 0)`.
        static func counter(_ value: Any?) -> Int {
            switch value {
            case let number as Int: return number
            case let number as Double: return Int(number)
            case let text as String: return Int(text) ?? 0
            default: return 0
            }
        }
    }
}
