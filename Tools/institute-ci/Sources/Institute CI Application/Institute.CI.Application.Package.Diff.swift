import CI_Contract
import Foundation
import Institute_Receipt

extension Institute.CI.Application {
    /// Complete GitHub event-diff retrieval for package-work planning.
    /// Workflow wiring passes coordinates only; pagination and classification
    /// live in the Swift CI owner.
    public enum PackageDiff {
        enum Error: Swift.Error { case event, comparison, response }

        public static func packageContentChanged(
            event: String,
            eventPath: String,
            repository: String,
            workspace: String
        ) -> Bool {
            guard event == "pull_request" || event == "push" else { return true }
            do throws(Error) {
                let payload = try eventPayload(at: eventPath)
                let changes: [CI.Contract.Package.Content.Change]
                if event == "pull_request" {
                    guard let number = payload["number"] as? Int else { throw .event }
                    changes = try files(
                        at: "repos/\(repository)/pulls/\(number)/files?per_page=100"
                    )
                } else {
                    guard let before = payload["before"] as? String,
                        let after = payload["after"] as? String,
                        !isZero(before), !isZero(after)
                    else { throw .comparison }
                    changes = try pushChanges(repository: repository, before: before, after: after)
                }
                return CI.Contract.Package.Content(declaredRoots: packageRoots(in: workspace))
                    .changed(changes)
            } catch { return true }
        }

        static func eventPayload(at path: String) throws(Error) -> [String: Any] {
            guard let data = FileManager.default.contents(atPath: path) else { throw .event }
            // swift-linter:disable:next try optional
            // REASON: JSONSerialization reports an untyped decoding error; an unreadable event is fail-closed.
            // swiftlint:disable:next no_try_optional
            guard let object = try? JSONSerialization.jsonObject(with: data) else { throw .event }
            guard let payload = object as? [String: Any] else { throw .event }
            return payload
        }

        static func pushChanges(
            repository: String,
            before: String,
            after: String
        ) throws(Error) -> [CI.Contract.Package.Content.Change] {
            let pages = try objects(
                at: "repos/\(repository)/compare/\(before)...\(after)?per_page=100"
            )
            guard !pages.isEmpty else { throw .comparison }
            let expected = pages.compactMap { $0["total_commits"] as? Int }.max() ?? 0
            let commits = Set(
                pages.flatMap {
                    ($0["commits"] as? [[String: Any]] ?? [])
                        .compactMap { $0["sha"] as? String }
                }
            )
            guard commits.count == expected else { throw .comparison }
            var changes: [CI.Contract.Package.Content.Change] = []
            for commit in commits.sorted() {
                changes += try files(at: "repos/\(repository)/commits/\(commit)?per_page=100")
            }
            return changes
        }

        static func files(at endpoint: String) throws(Error) -> [CI.Contract.Package.Content.Change]
        {
            try objects(at: endpoint).flatMap { object in
                let files: [[String: Any]] = object["files"] as? [[String: Any]] ?? [object]
                return files.compactMap { file -> CI.Contract.Package.Content.Change? in
                    guard let path = file["filename"] as? String else { return nil }
                    return .init(path: path, previousPath: file["previous_filename"] as? String)
                }
            }
        }

        static func objects(at endpoint: String) throws(Error) -> [[String: Any]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "api", "--paginate", "--slurp", endpoint]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.standardError
            // swift-linter:disable:next try optional
            // REASON: Process.run reports an untyped Foundation error; an unavailable client is fail-closed.
            // swiftlint:disable:next no_try_optional
            guard (try? process.run()) != nil else { throw .response }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw .response }
            // swift-linter:disable:next try optional
            // REASON: JSONSerialization reports an untyped decoding error; an unreadable response is fail-closed.
            // swiftlint:disable no_try_optional
            guard
                let object = try? JSONSerialization.jsonObject(
                    with: output.fileHandleForReading.readDataToEndOfFile()
                )
            else { throw .response }
            // swiftlint:enable no_try_optional
            return flatten(object)
        }

        static func flatten(_ object: Any) -> [[String: Any]] {
            if let dictionary = object as? [String: Any] { return [dictionary] }
            if let array = object as? [Any] { return array.flatMap(flatten) }
            return []
        }

        static func packageRoots(in workspace: String) -> [String] {
            guard let enumerator = FileManager.default.enumerator(atPath: workspace) else {
                return []
            }
            var roots: [String] = []
            for case let path as String in enumerator {
                if path.hasPrefix(".git/") || path.hasPrefix(".build/")
                    || path.hasPrefix(".swiftpm/")
                {
                    enumerator.skipDescendants()
                } else if path == "Package.swift" {
                    roots.append("")
                } else if path.hasSuffix("/Package.swift") {
                    roots.append(String(path.dropLast("Package.swift".count + 1)))
                }
            }
            return roots
        }

        static func isZero(_ revision: String) -> Bool {
            revision.count == 40 && revision.allSatisfy { $0 == "0" }
        }
    }
}
