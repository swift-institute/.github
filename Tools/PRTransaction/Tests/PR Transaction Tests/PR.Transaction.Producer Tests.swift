import Foundation
import Testing

@testable import PR_Transaction

extension PRTransaction.Transaction {
    @Suite struct Producer {
        private var head: String { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
        private var old: String { "cccccccccccccccccccccccccccccccccccccccc" }
        private var control: PRTransaction.Snapshot.Verification {
            .control(checks: ["fixtures", "correspondence", "scan"])
        }

        @Test func `package plan survives producer JSON and CLI validation`() throws {
            let output = try produce("package-source")
            defer { try? FileManager.default.removeItem(at: output) }

            let snapshot = try decode(output)
            #expect(snapshot.repository == "swift-foundations/swift-tests")
            #expect(snapshot.pull == 8)
            #expect(snapshot.plan.repository == snapshot.repository)
            #expect(snapshot.plan.pull == snapshot.pull)
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

        @Test func `CLI rejects a private target repository`() throws {
            #expect(throws: PRTransaction.Error.invalidTarget) {
                try PRTransaction.Command.run(["produce", fixture("private-target-source").path])
            }
        }

        @Test func `producer rejects a target response for another repository`() {
            let source = source(
                verification: control,
                checks: pages([[check("fixtures"), check("correspondence"), check("scan")]]),
                target: .init(repository: "swift-foundations/swift-tests", visibility: "public")
            )

            #expect(throws: PRTransaction.Error.invalidTarget) {
                try source.snapshot()
            }
        }

        @Test func `producer rejects a target response without visibility`() {
            let data = Data(#"""
                { "repository": "swift-institute/.github", "target": { "repository": "swift-institute/.github" } }
                """#.utf8)

            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(PRTransaction.Snapshot.Source.self, from: data)
            }
        }

        @Test func `CLI rejects a legacy snapshot missing task and profiles`() throws {
            #expect(throws: DecodingError.self) {
                try PRTransaction.Command.run(["review", fixture("legacy-snapshot").path])
            }
        }

        @Test func `paginated review response flattens every REST page`() throws {
            let pages = try JSONDecoder().decode(
                [[Review]].self,
                from: Data(contentsOf: try fixture("review-pages"))
            )

            #expect(
                pages.flatMap { $0 }.map(\.actor)
                    == ["first-reviewer", "second-reviewer", "third-reviewer"]
            )
        }

        @Test func `producer rejects a failed duplicate check after the first hundred`() throws {
            let first = requiredChecks()
            #expect(first.count == 100)
            let source = source(
                verification: control,
                checks: pages([first, [check("scan", conclusion: "failure")]])
            )

            #expect(throws: PRTransaction.Error.unsuccessful("scan")) {
                try PRTransaction.review(source.snapshot())
            }
        }

        @Test func `producer rejects a nonterminal duplicate check after the first hundred`() throws
        {
            let first = requiredChecks()
            #expect(first.count == 100)
            let source = source(
                verification: control,
                checks: pages([first, [check("scan", conclusion: nil)]])
            )

            #expect(throws: PRTransaction.Error.nonterminal("scan")) {
                try PRTransaction.review(source.snapshot())
            }
        }

        @Test func `producer accepts complete clean checks beyond the first hundred`() throws {
            let first = requiredChecks()
            #expect(first.count == 100)
            let source = source(
                verification: control,
                checks: pages([first, [check("scan")]])
            )

            #expect(try PRTransaction.review(source.snapshot()) == .readyForReview)
        }

        @Test func `producer rejects a failed duplicate workflow run after the first hundred`()
            throws
        {
            let first = workflowRuns()
            #expect(first.count == 100)
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]]),
                runs: pages([first, [run("CI", conclusion: "failure")]])
            )

            #expect(throws: PRTransaction.Error.nonterminalFullTier) {
                try PRTransaction.review(source.snapshot())
            }
        }

        @Test func `producer rejects a nonterminal workflow run after the first hundred`() throws {
            let first = workflowRuns()
            #expect(first.count == 100)
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]]),
                runs: pages([first, [run("CI", conclusion: nil)]])
            )

            #expect(throws: PRTransaction.Error.nonterminalFullTier) {
                try PRTransaction.review(source.snapshot())
            }
        }

        @Test func `producer accepts complete clean workflow runs beyond the first hundred`() throws
        {
            let first = workflowRuns()
            #expect(first.count == 100)
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]]),
                runs: pages([first, [run("CI")]])
            )

            #expect(try PRTransaction.review(source.snapshot()) == .readyForReview)
        }

        @Test func `full tier ignores the retired swift-ci workflow name`() {
            // The fleet thin caller is named `CI`; a run under the retired
            // `swift-ci` name must synthesize no full-tier evidence.
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]]),
                runs: pages([[run("swift-ci")]])
            )

            #expect(throws: PRTransaction.Error.nonterminalFullTier) {
                try PRTransaction.review(source.snapshot())
            }
        }

        @Test func `full tier ignores a pull-request run of the caller workflow`() {
            // Tier follows the event: only the workflow_dispatch run of the
            // caller is the full tier. A pull_request run of the same
            // workflow is a lower tier and must not stand in for it.
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]]),
                runs: pages([[run("CI", event: "pull_request")]])
            )

            #expect(throws: PRTransaction.Error.nonterminalFullTier) {
                try PRTransaction.review(source.snapshot())
            }
        }

        @Test func `producer rejects an incomplete check-run collection`() {
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]], total: 2)
            )

            #expect(throws: PRTransaction.Error.incomplete("check-runs")) {
                try source.snapshot()
            }
        }

        @Test func `producer rejects an incomplete workflow-run collection`() {
            let source = source(
                verification: .package,
                checks: pages([[check("ci / ci-ok")]]),
                runs: pages([[run("CI")]], total: 2)
            )

            #expect(throws: PRTransaction.Error.incomplete("workflow-runs")) {
                try source.snapshot()
            }
        }

        private func decode(_ url: URL) throws -> PRTransaction.Snapshot {
            try JSONDecoder().decode(PRTransaction.Snapshot.self, from: Data(contentsOf: url))
        }

        private struct Review: Decodable {
            let actor: String

            private enum CodingKeys: String, CodingKey {
                case user
            }

            private enum UserCodingKeys: String, CodingKey {
                case login
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let user = try container.nestedContainer(keyedBy: UserCodingKeys.self, forKey: .user)
                actor = try user.decode(String.self, forKey: .login)
            }
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

        private func check(
            _ name: String,
            conclusion: String? = "success"
        ) -> PRTransaction.Snapshot.Check {
            .init(name: name, head: head, conclusion: conclusion)
        }

        private func run(
            _ name: String,
            event: String = "workflow_dispatch",
            conclusion: String? = "success"
        ) -> PRTransaction.Snapshot.Source.Run {
            .init(name: name, event: event, head: head, conclusion: conclusion)
        }

        private func pages<Element: Codable & Sendable>(
            _ values: [[Element]],
            total: Int? = nil
        ) -> [PRTransaction.Snapshot.Source.Page<Element>] {
            let declared = total ?? values.reduce(0) { $0 + $1.count }
            return values.map { .init(total: declared, values: $0) }
        }

        private func requiredChecks() -> [PRTransaction.Snapshot.Check] {
            [check("fixtures"), check("correspondence"), check("scan")]
                + (0..<97).map { check("unrelated-\($0)") }
        }

        private func workflowRuns() -> [PRTransaction.Snapshot.Source.Run] {
            [run("CI")]
                + (0..<99).map { run("unrelated-workflow-\($0)") }
        }

        private func source(
            verification: PRTransaction.Snapshot.Verification,
            checks: [PRTransaction.Snapshot.Source.Page<PRTransaction.Snapshot.Check>],
            target: PRTransaction.Snapshot.Source.Target = .init(
                repository: "swift-institute/.github",
                visibility: "public"
            ),
            runs: [PRTransaction.Snapshot.Source.Page<PRTransaction.Snapshot.Source.Run>] = [
                .init(total: 0, values: [])
            ]
        ) -> PRTransaction.Snapshot.Source {
            let task = PRTransaction.Snapshot.Issue(
                repository: "swift-institute/.github",
                number: 188,
                state: "OPEN"
            )
            return PRTransaction.Snapshot.Source(
                repository: "swift-institute/.github",
                target: target,
                pull: 189,
                base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                head: head,
                fixer: "coenttb",
                owningTask: task,
                plan: .init(
                    accepted: true,
                    repository: "swift-institute/.github",
                    pull: 189,
                    base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    head: head,
                    task: task,
                    verification: verification,
                    paths: [".github/workflows/review-pr-transaction.yml"],
                    evidence: [
                        .init(command: "workspace package test", result: "success", head: head)
                    ],
                    payloadPreflighted: true,
                    nextOwner: "swift-institute-bot[bot]"
                ),
                reviews: [],
                checkPages: checks,
                runPages: runs,
                unresolvedThreads: 0,
                merge: .init(squash: true, mergeCommit: false, rebase: false)
            )
        }
    }
}
