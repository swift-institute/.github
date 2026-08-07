import Foundation

extension Repository.Policy {
    /// The canonical non-Swift executable census (FT1-frozen sixteen-field
    /// schema, censusVersion 1). Owns serialization; scanning lives in
    /// `Repository.Policy.Census.Generator`.
    public struct Census: Sendable, Equatable {
        public var rows: [Row]

        public init(rows: [Row]) {
            self.rows = rows
        }

        public static let fields: [String] = [
            "censusVersion", "repository", "headSha", "path",
            "coordinateKind", "coordinateId", "line", "engine",
            "excerptSha256", "family", "intendedOwner", "disposition",
            "measurement", "cause", "generatedBy", "notes",
        ]

        /// CSV bytes with minimal quoting and `\n` terminators — the exact
        /// dialect of the FT1 census artifact.
        public var csv: String {
            var out = Self.fields.map(Self.quoted).joined(separator: ",") + "\n"
            for row in rows {
                out += row.values.map(Self.quoted).joined(separator: ",") + "\n"
            }
            return out
        }

        /// Rows sorted by coordinate identity, for order-normalized parity
        /// between generators whose directory traversal order differs.
        public var normalized: Census {
            Census(rows: rows.sorted { ($0.repository, $0.path, $0.coordinateId) < ($1.repository, $1.path, $1.coordinateId) })
        }

        public static func quoted(_ field: String) -> String {
            guard field.contains(",") || field.contains("\"")
                || field.contains("\n") || field.contains("\r") else {
                return field
            }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }
}
