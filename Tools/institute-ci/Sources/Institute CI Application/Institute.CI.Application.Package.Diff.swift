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
            do throws(Error) {
                let payload = try eventPayload(at: eventPath)
                return packageContentChanged(
                    event: event,
                    payload: payload,
                    repository: repository,
                    workspace: workspace,
                    response: response(at:)
                )
            } catch { return true }
        }

        static func packageContentChanged(
            event: String,
            payload: [String: Any],
            repository: String,
            workspace: String,
            response: (String) throws(Error) -> Data
        ) -> Bool {
            guard event == "pull_request" || event == "push" else { return true }
            do throws(Error) {
                let changes: [CI.Contract.Package.Content.Change]
                if event == "pull_request" {
                    guard let number = payload["number"] as? Int else { throw .event }
                    changes = try files(
                        at: "repos/\(repository)/pulls/\(number)/files?per_page=100",
                        response: response
                    )
                } else {
                    guard let before = payload["before"] as? String,
                        let after = payload["after"] as? String,
                        !isZero(before), !isZero(after)
                    else { throw .comparison }
                    changes = try pushChanges(
                        repository: repository,
                        before: before,
                        after: after,
                        response: response
                    )
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
            after: String,
            response: (String) throws(Error) -> Data
        ) throws(Error) -> [CI.Contract.Package.Content.Change] {
            let pages = try objects(
                at: "repos/\(repository)/compare/\(before)...\(after)?per_page=100",
                response: response
            )
            guard !pages.isEmpty else { throw .comparison }
            guard let expected = pages.first?["total_commits"] as? Int, expected >= 0 else {
                throw .comparison
            }
            var commits: [String] = []
            for page in pages {
                guard page["total_commits"] as? Int == expected,
                    let records = page["commits"] as? [Any]
                else { throw .comparison }
                for record in records {
                    guard let object = record as? [String: Any],
                        let sha = object["sha"] as? String,
                        !sha.isEmpty
                    else { throw .comparison }
                    commits.append(sha)
                }
            }
            guard commits.count == expected, Set(commits).count == expected else { throw .comparison }
            var changes: [CI.Contract.Package.Content.Change] = []
            for commit in commits {
                changes += try files(
                    at: "repos/\(repository)/commits/\(commit)?per_page=100",
                    response: response
                )
            }
            return changes
        }

        static func files(
            at endpoint: String,
            response: (String) throws(Error) -> Data
        ) throws(Error) -> [CI.Contract.Package.Content.Change] {
            var changes: [CI.Contract.Package.Content.Change] = []
            for page in try pages(from: response(endpoint)) {
                let records: [Any]
                if let object = page as? [String: Any] {
                    guard let files = object["files"] as? [Any] else { throw .response }
                    records = files
                } else if let array = page as? [Any] {
                    records = array
                } else {
                    throw .response
                }
                for record in records {
                    guard let file = record as? [String: Any],
                        let path = file["filename"] as? String,
                        !path.isEmpty
                    else { throw .response }
                    let previousPath: String?
                    if let previous = file["previous_filename"] {
                        guard let path = previous as? String, !path.isEmpty else { throw .response }
                        previousPath = path
                    } else {
                        previousPath = nil
                    }
                    changes.append(.init(path: path, previousPath: previousPath))
                }
            }
            return changes
        }

        static func objects(
            at endpoint: String,
            response: (String) throws(Error) -> Data
        ) throws(Error) -> [[String: Any]] {
            var objects: [[String: Any]] = []
            for page in try pages(from: response(endpoint)) {
                guard let object = page as? [String: Any] else { throw .response }
                objects.append(object)
            }
            return objects
        }

        static func response(at endpoint: String) throws(Error) -> Data {
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
            return output.fileHandleForReading.readDataToEndOfFile()
        }

        static func pages(from data: Data) throws(Error) -> [Any] {
            // swift-linter:disable:next try optional
            // REASON: JSONSerialization reports an untyped decoding error; malformed complete-diff output is fail-closed.
            // swiftlint:disable:next no_try_optional
            guard let object = try? JSONSerialization.jsonObject(with: data),
                let pages = object as? [Any],
                !pages.isEmpty
            else { throw .response }
            return pages
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
