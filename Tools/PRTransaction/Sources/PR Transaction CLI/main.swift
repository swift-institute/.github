import Foundation
import PR_Transaction

enum Main {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 2, let operation = arguments.first, let path = arguments.last
            else {
                throw UsageError()
            }
            let snapshot = try JSONDecoder().decode(
                PRTransaction.Snapshot.self,
                from: Data(contentsOf: URL(fileURLWithPath: path))
            )
            let verdict: PRTransaction.Verdict
            switch operation {
            case "review": verdict = try PRTransaction.review(snapshot)
            case "merge": verdict = try PRTransaction.merge(snapshot)
            case "complete": verdict = try PRTransaction.complete(snapshot)
            default: throw UsageError()
            }
            print("pr-transaction: \(verdict.rawValue) head=\(snapshot.head)")
        } catch {
            fputs("pr-transaction: \(error)\n", stderr)
            exit(1)
        }
    }

    struct UsageError: Swift.Error {}
}

Main.main()
