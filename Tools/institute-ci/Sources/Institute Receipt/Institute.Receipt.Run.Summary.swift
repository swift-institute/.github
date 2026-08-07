public import Byte_Primitives
import Foundation

extension Institute.Receipt.Run {
    /// One row of an Actions runs collection, as the probe reads it.
    ///
    /// Deliberately thinner than `Institute.Receipt.Run`: that type is a
    /// run's *attested identity*, and everything on it participates in a
    /// receipt. This is what a scan over many runs needs to report one —
    /// the conclusion it is judged by, and enough coordinate to open it.
    public struct Summary: Sendable, Equatable {
        public let id: Int?
        public let name: String?
        public let conclusion: Institute.Receipt.Conclusion?
        public let htmlURL: String?

        public init(
            id: Int?,
            name: String?,
            conclusion: Institute.Receipt.Conclusion?,
            htmlURL: String?
        ) {
            self.id = id
            self.name = name
            self.conclusion = conclusion
            self.htmlURL = htmlURL
        }
    }
}

extension Institute.Receipt.Run.Summary {
    public enum Error: Swift.Error, Sendable, Equatable {
        case malformed(String)
    }

    /// Every run in an Actions runs payload.
    ///
    /// Accepts the REST object (`{"workflow_runs": […]}`) and a bare
    /// array, because the probe's `gh api --paginate --slurp` pipeline
    /// produces the first and a hand-written fixture the second. Any
    /// other shape carries no runs — which is not an error, it is a
    /// collection of zero runs, and a scan over zero runs is clean.
    public static func collection(_ payload: [Byte]) throws(Error) -> [Self] {
        let data = Data(payload.map(\.underlying))
        // swift-linter:disable:next try optional
        // REASON: JSONSerialization.jsonObject throws untyped; the refusal it maps to is this function's own typed error.
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            throw .malformed("invalid JSON input")
        }
        let rows: [[String: Any]]
        if let object = decoded as? [String: Any] {
            rows = object["workflow_runs"] as? [[String: Any]] ?? []
        } else {
            rows = decoded as? [[String: Any]] ?? []
        }
        return rows.map {
            .init(
                id: $0["id"] as? Int,
                name: $0["name"] as? String,
                conclusion: ($0["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) },
                htmlURL: $0["html_url"] as? String)
        }
    }
}
