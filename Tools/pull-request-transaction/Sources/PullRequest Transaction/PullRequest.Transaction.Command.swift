import Foundation

extension PullRequest.Transaction {
    /// The file-backed command boundary used by the `pr-transaction` executable.
    public enum Command {
        /// Executes one guarded operation against a serialized transaction snapshot.
        public static func run(_ arguments: [String]) throws -> String {
            guard arguments.count == 2, let operation = arguments.first, let path = arguments.last
            else {
                throw Error.usage
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if operation == "produce" {
                let source = try JSONDecoder().decode(Snapshot.Source.self, from: data)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return String(decoding: try encoder.encode(source.snapshot()), as: UTF8.self)
            }
            if operation == "post-merge" {
                let watch = try JSONDecoder().decode(PostMerge.Watch.self, from: data)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                return String(decoding: try encoder.encode(PostMerge.report(for: watch)), as: UTF8.self)
            }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            let verdict: Verdict
            switch operation {
            case "review": verdict = try PullRequest.Transaction.review(snapshot)
            case "merge": verdict = try PullRequest.Transaction.merge(snapshot)
            case "complete": verdict = try PullRequest.Transaction.complete(snapshot)
            default: throw Error.usage
            }
            return "pr-transaction: \(verdict.rawValue) head=\(snapshot.head)"
        }

        public enum Error: Swift.Error {
            case usage
        }
    }
}
