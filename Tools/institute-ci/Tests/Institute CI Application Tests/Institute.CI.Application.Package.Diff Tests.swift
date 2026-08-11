@testable import Institute_CI_Application
import Foundation
import Institute_Receipt
import Testing

@Suite
struct `Package Diff Tests` {
    @Test func `complete pagination and rename select package work`() throws {
        try withWorkspace { workspace in
            let response = try JSONSerialization.data(withJSONObject: [
                [["filename": "Research/receipt.md"]],
                [["filename": "Research/moved.md", "previous_filename": "Sources/Library/Value.swift"]],
            ])
            let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                event: "pull_request",
                payload: ["number": 1, "pull_request": ["changed_files": 2]],
                repository: "o/r",
                workspace: workspace,
                response: { _ in response }
            )
            #expect(changed)
        }
    }

    @Test func `valid non-package files do not select package work`() throws {
        try withWorkspace { workspace in
            let response = try JSONSerialization.data(withJSONObject: [[
                ["filename": "Research/receipt.md"],
            ]])
            let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                event: "pull_request",
                payload: ["number": 1, "pull_request": ["changed_files": 1]],
                repository: "o/r",
                workspace: workspace,
                response: { _ in response }
            )
            #expect(!changed)
        }
    }

    @Test(arguments: [
        "{}",
        "[\"malformed page\"]",
        "[[{}]]",
        "[[{\"filename\": 1}]]",
    ])
    func `malformed successful file response selects package work`(response: String) throws {
        try withWorkspace { workspace in
            let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                event: "pull_request",
                payload: ["number": 1, "pull_request": ["changed_files": 1]],
                repository: "o/r",
                workspace: workspace,
                response: { _ in Data(response.utf8) }
            )
            #expect(changed)
        }
    }

    @Test func `incomplete comparison enumeration selects package work`() throws {
        try withWorkspace { workspace in
            let response = try JSONSerialization.data(withJSONObject: [[
                "total_commits": 2,
                "commits": [["sha": "a"]],
            ]])
            let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                event: "push",
                payload: [
                    "before": String(repeating: "a", count: 40),
                    "after": String(repeating: "b", count: 40),
                ],
                repository: "o/r",
                workspace: workspace,
                response: { _ in response }
            )
            #expect(changed)
        }
    }

    @Test func `missing invalid or capped pull request count selects package work`() throws {
        try withWorkspace { workspace in
            let response = try JSONSerialization.data(withJSONObject: [[
                ["filename": "Research/receipt.md"],
            ]])
            for pullRequest: [String: Any] in [
                [:],
                ["changed_files": "1"],
                ["changed_files": true],
                ["changed_files": 1.0],
                ["changed_files": -1],
                ["changed_files": 3_000],
            ] {
                let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                    event: "pull_request",
                    payload: ["number": 1, "pull_request": pullRequest],
                    repository: "o/r",
                    workspace: workspace,
                    response: { _ in response }
                )
                #expect(changed)
            }
        }
    }

    @Test(arguments: [
        (1, [["filename": "Research/receipt.md"], ["filename": "Research/other.md"]]),
        (2, [["filename": "Research/receipt.md"], ["filename": "Research/receipt.md"]]),
        (2, [
            ["filename": "Research/receipt.md", "previous_filename": "Research/old-a.md"],
            ["filename": "Research/receipt.md", "previous_filename": "Research/old-b.md"],
        ]),
    ])
    func `mismatched or duplicate pull request records select package work`(
        expected: Int,
        records: [[String: String]]
    ) throws {
        try withWorkspace { workspace in
            let response = try JSONSerialization.data(withJSONObject: [records])
            let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                event: "pull_request",
                payload: ["number": 1, "pull_request": ["changed_files": expected]],
                repository: "o/r",
                workspace: workspace,
                response: { _ in response }
            )
            #expect(changed)
        }
    }

    @Test func `complete pull request count immediately below cap remains non package work`() throws {
        try withWorkspace { workspace in
            let expected = Institute.CI.Application.PackageDiff.pullRequestFileLimit - 1
            let records = (0..<expected).map { ["filename": "Research/\($0).md"] }
            let response = try JSONSerialization.data(withJSONObject: [records])
            let changed = Institute.CI.Application.PackageDiff.packageContentChanged(
                event: "pull_request",
                payload: ["number": 1, "pull_request": ["changed_files": expected]],
                repository: "o/r",
                workspace: workspace,
                response: { _ in response }
            )
            #expect(!changed)
        }
    }

    private func withWorkspace(_ body: (String) throws -> Void) throws {
        let workspace = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        // swift-linter:disable:next try optional
        // REASON: FileManager cleanup reports an untyped error and cannot mask the test result.
        // swiftlint:disable:next no_try_optional
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data().write(to: workspace.appending(path: "Package.swift"))
        try body(workspace.path())
    }
}
