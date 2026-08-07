import CI_Contract
import Testing

@testable import CI_Workflow

@Suite
struct CIWorkflowDocumentTests {
    static let caller = """
        name: CI

        on:
          push:
            branches: [main]
          pull_request:

        jobs:
          ci:
            uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
            secrets: inherit
          lint:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v6
        """

    @Suite
    struct Unit {
        @Test func `jobs keep document order`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml", text: CIWorkflowDocumentTests.caller)
            #expect(document.jobs.map(\.name) == ["ci", "lint"])
        }

        @Test func `caller jobs are distinguished from regular jobs`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml", text: CIWorkflowDocumentTests.caller)
            #expect(document.jobs[0].isCaller)
            #expect(document.jobs[0].uses?.hasSuffix("swift-ci.yml@main") == true)
            #expect(!document.jobs[1].isCaller)
            #expect(document.jobs[1].runsOn == .text("ubuntu-latest"))
            #expect(document.jobs[1].steps.count == 1)
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `triggers recover the boolean on key`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml", text: CIWorkflowDocumentTests.caller)
            #expect(try #require(document.triggers).textKeys == ["push", "pull_request"])
        }

        @Test func `non map trigger shapes have no map form`() throws {
            #expect(try CI.Workflow.Document(name: "a.yml", text: "on: push\n").triggers == nil)
            #expect(try CI.Workflow.Document(name: "b.yml", text: "on: [push]\n").triggers == nil)
            #expect(try CI.Workflow.Document(name: "c.yml", text: "name: x\n").triggers == nil)
        }

        @Test func `malformed jobs are skipped not reported`() throws {
            // Several rules depend on this: `iter_jobs` skipped them too.
            let document = try CI.Workflow.Document(
                name: "ci.yml",
                text: "jobs:\n  good:\n    uses: a/b@main\n  bad: not-a-mapping\n")
            #expect(document.jobs.map(\.name) == ["good"])
        }

        @Test func `non mapping root means nothing to check`() throws {
            let document = try CI.Workflow.Document(name: "ci.yml", text: "- just\n- a list\n")
            #expect(document.body == nil)
            #expect(document.jobs.isEmpty)
            #expect(document.triggers == nil)
        }

        @Test func `blank uses is not a caller job`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml", text: "jobs:\n  a:\n    uses: '  '\n")
            #expect(!document.jobs[0].isCaller)
        }
    }

    @Suite
    struct Integration {
        @Test func `a caller document reads end to end`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml", text: CIWorkflowDocumentTests.caller)
            #expect(document.name == "ci.yml")
            #expect(document.body != nil)
            #expect(document.triggers != nil)
            #expect(document.jobs.count == 2)
        }
    }
}
