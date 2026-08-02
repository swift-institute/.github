import Foundation
import Testing

@testable import PR_Transaction

extension PRTransaction.Transaction {
    @Suite struct Producer {
        private var head: String { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
        private var old: String { "cccccccccccccccccccccccccccccccccccccccc" }

        @Test func `package plan survives producer JSON and CLI validation`() throws {
            let output = try produce("package-source")
            defer { try? FileManager.default.removeItem(at: output) }

            let snapshot = try decode(output)
            #expect(snapshot.plan.task == snapshot.owningTask)
            #expect(snapshot.plan.verification == .package)
            #expect(snapshot.plan.payload.verification == .package)
            #expect(
                try PRTransaction.Command.run(["review", output.path])
                    == "pr-transaction: ready-for-bot-review head=\(head)"
            )
        }

        @Test func `control plan survives producer JSON and CLI validation`() throws {
            let output = try produce("control-source")
            defer { try? FileManager.default.removeItem(at: output) }

            let verification = PRTransaction.Snapshot.Verification.control(
                checks: ["fixtures", "correspondence", "scan"]
            )
            let snapshot = try decode(output)
            #expect(snapshot.plan.task == snapshot.owningTask)
            #expect(snapshot.plan.verification == verification)
            #expect(snapshot.plan.payload.verification == verification)
            #expect(
                try PRTransaction.Command.run(["review", output.path])
                    == "pr-transaction: ready-for-bot-review head=\(head)"
            )
        }

        @Test func `CLI rejects a stale producer plan`() throws {
            let output = try produce("stale-source")
            defer { try? FileManager.default.removeItem(at: output) }

            #expect(throws: PRTransaction.Error.stalePlanHead(expected: head, actual: old)) {
                try PRTransaction.Command.run(["review", output.path])
            }
        }

        @Test func `CLI rejects a legacy snapshot missing task and profiles`() throws {
            #expect(throws: DecodingError.self) {
                try PRTransaction.Command.run(["review", fixture("legacy-snapshot").path])
            }
        }

        private func decode(_ url: URL) throws -> PRTransaction.Snapshot {
            try JSONDecoder().decode(PRTransaction.Snapshot.self, from: Data(contentsOf: url))
        }

        private func fixture(_ name: String) throws -> URL {
            try #require(
                Bundle.module.url(
                    forResource: name,
                    withExtension: "json",
                    subdirectory: "Fixtures"
                )
            )
        }

        private func produce(_ name: String) throws -> URL {
            let output = FileManager.default.temporaryDirectory
                .appending(path: "pr-transaction-\(UUID().uuidString).json")
            let json = try PRTransaction.Command.run(["produce", fixture(name).path])
            try Data(json.utf8).write(to: output)
            return output
        }
    }
}
