import Foundation
import Testing

@testable import PR_Transaction

extension PRTransaction.Transaction {
    @Suite struct PostMerge {
        private var head: String { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }

        // MARK: - classify(_:) — the outcome-classification logic extracted
        // from verify-post-merge.yml (swift-institute/.github#213). A lost
        // watch is not-green: every branch but a confirmed success/success
        // pair must classify as `.lost`, never `.green` and never silently
        // absent.

        @Test func `classifies a confirmed green watch`() {
            let watch = PRTransaction.PostMerge.Watch(
                repository: "swift-foundations/swift-tests",
                expectedHead: head,
                stepOutcome: "success",
                conclusion: "success",
                runURL: "https://github.com/swift-foundations/swift-tests/actions/runs/1",
                lostReason: nil
            )
            #expect(
                PRTransaction.PostMerge.classify(watch)
                    == .green(runURL: "https://github.com/swift-foundations/swift-tests/actions/runs/1")
            )
        }

        @Test func `classifies a confirmed red watch`() {
            let watch = PRTransaction.PostMerge.Watch(
                repository: "swift-foundations/swift-tests",
                expectedHead: head,
                stepOutcome: "success",
                conclusion: "failure",
                runURL: "https://github.com/swift-foundations/swift-tests/actions/runs/2",
                lostReason: nil
            )
            #expect(
                PRTransaction.PostMerge.classify(watch)
                    == .red(
                        conclusion: "failure",
                        runURL: "https://github.com/swift-foundations/swift-tests/actions/runs/2"
                    )
            )
        }

        @Test func `classifies a cancelled dispatch step as a lost watch, not silence`() {
            // The job-timeout case (verify-post-merge.yml's own documented
            // queueing up to 7h41m against a 360-minute GitHub-hosted
            // ceiling): the dispatch step never sets `conclusion`, but its
            // own GitHub-native step result is `cancelled`.
            let watch = PRTransaction.PostMerge.Watch(
                repository: "swift-foundations/swift-tests",
                expectedHead: head,
                stepOutcome: "cancelled",
                conclusion: nil,
                runURL: nil,
                lostReason: nil
            )
            #expect(PRTransaction.PostMerge.classify(watch) == .lost(reason: .watchCancelled))
        }

        @Test func `classifies an explicit poll-timeout reason over the raw step outcome`() {
            let watch = PRTransaction.PostMerge.Watch(
                repository: "swift-foundations/swift-tests",
                expectedHead: head,
                stepOutcome: "failure",
                conclusion: nil,
                runURL: nil,
                lostReason: "poll-timed-out"
            )
            #expect(PRTransaction.PostMerge.classify(watch) == .lost(reason: .pollTimedOut))
        }

        @Test func `classifies an undiscovered run as a lost watch`() {
            let watch = PRTransaction.PostMerge.Watch(
                repository: "swift-foundations/swift-tests",
                expectedHead: head,
                stepOutcome: "failure",
                conclusion: nil,
                runURL: nil,
                lostReason: "run-not-discovered"
            )
            #expect(PRTransaction.PostMerge.classify(watch) == .lost(reason: .runNotDiscovered))
        }

        @Test func `classifies a successful step outcome missing its conclusion as lost, never green`() {
            // Defensive: `conclusion`/`runURL` absent despite a `success`
            // step outcome should not happen, but must still refuse to be
            // silently treated as green.
            let watch = PRTransaction.PostMerge.Watch(
                repository: "swift-foundations/swift-tests",
                expectedHead: head,
                stepOutcome: "success",
                conclusion: nil,
                runURL: nil,
                lostReason: nil
            )
            #expect(PRTransaction.PostMerge.classify(watch) == .lost(reason: .runNotDiscovered))
        }

        // MARK: - report(for:) and the Bug it files — the three mandated
        // fixtures (swift-institute/.github#213): red-run, verification-
        // lost, and green (no Bug).

        @Test func `green fixture reports green and files no Bug`() throws {
            let report = try report(fixture: "post-merge-green")
            #expect(report.outcome == "green")
            #expect(report.title == nil)
            #expect(report.body == nil)
        }

        @Test func `red-run fixture files a Bug naming the run and its conclusion`() throws {
            let report = try report(fixture: "post-merge-red")
            #expect(report.outcome == "red")
            let title = try #require(report.title)
            let body = try #require(report.body)
            #expect(title.contains("failure"))
            #expect(body.contains("concluded `failure`"))
            #expect(body.contains("actions/runs/456"))
            #expect(body.contains("### Observed behavior"))
            #expect(body.contains("### Expected behavior"))
            #expect(body.contains("### Minimal reproduction"))
            #expect(body.contains("### Swift version"))
            #expect(body.contains("### Platform"))
            #expect(body.contains("### Additional context"))
        }

        @Test func `verification-lost fixture files a Bug naming the lost class, not the absent conclusion`()
            throws
        {
            let report = try report(fixture: "post-merge-lost")
            #expect(report.outcome == "lost")
            let title = try #require(report.title)
            let body = try #require(report.body)
            #expect(title.contains("watch-cancelled"))
            #expect(body.contains("watch-cancelled"))
            #expect(body.contains("not-green"))
            #expect(body.contains("### Observed behavior"))
            #expect(body.contains("### Additional context"))
        }

        // Positive control: the CLI's `post-merge` operation reaches the
        // same classification through the file-backed command boundary
        // every other operation uses, not a bespoke path.
        @Test func `CLI post-merge operation round-trips the green fixture`() throws {
            let json = try PRTransaction.Command.run(["post-merge", fixture("post-merge-green").path])
            let decoded = try JSONDecoder().decode(
                PRTransaction.PostMerge.Report.self,
                from: Data(json.utf8)
            )
            #expect(decoded.outcome == "green")
        }

        @Test func `CLI post-merge operation round-trips the red fixture`() throws {
            let json = try PRTransaction.Command.run(["post-merge", fixture("post-merge-red").path])
            let decoded = try JSONDecoder().decode(
                PRTransaction.PostMerge.Report.self,
                from: Data(json.utf8)
            )
            #expect(decoded.outcome == "red")
            #expect(decoded.title != nil)
            #expect(decoded.body != nil)
        }

        private func report(fixture name: String) throws -> PRTransaction.PostMerge.Report {
            let watch = try JSONDecoder().decode(
                PRTransaction.PostMerge.Watch.self,
                from: Data(contentsOf: try fixture(name))
            )
            return PRTransaction.PostMerge.report(for: watch)
        }

        private func fixture(_ name: String) throws -> URL {
            try #require(
                Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            )
        }
    }
}
