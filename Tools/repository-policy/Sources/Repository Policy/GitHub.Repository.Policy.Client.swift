#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation

extension RepositoryPolicy {
    public struct GitHubClient: Sendable {
        public struct Error: Swift.Error, CustomStringConvertible, Sendable {
            public let method: String
            public let path: String
            public let status: Int
            public let response: String

            public var description: String {
                "\(method) \(path) returned HTTP \(status): \(response)"
            }
        }

        private let token: String
        private let baseURL: URL

        public init(token: String, baseURL: URL) {
            self.token = token
            self.baseURL = baseURL
        }

        public func repositories(organization: String) async throws -> [Repository] {
            var page = 1
            var result = [Repository]()
            while true {
                let path = "/orgs/\(organization)/repos?type=public&per_page=100&page=\(page)"
                let response = try await request(method: "GET", path: path)
                guard response.status == 200 else {
                    throw error(method: "GET", path: path, response: response)
                }
                let repositories = try JSONDecoder().decode([Repository].self, from: response.data)
                result.append(contentsOf: repositories)
                guard repositories.count == 100 else { return result }
                page += 1
            }
        }

        public func repository(_ fullName: String) async throws -> Repository {
            let path = "/repos/\(fullName)"
            let response = try await request(method: "GET", path: path)
            guard response.status == 200 else {
                throw error(method: "GET", path: path, response: response)
            }
            return try JSONDecoder().decode(Repository.self, from: response.data)
        }

        public func rootManifestKind(_ fullName: String) async throws -> String? {
            let path = "/repos/\(fullName)/contents/Package.swift"
            let response = try await request(method: "GET", path: path)
            if response.status == 404 { return nil }
            guard response.status == 200 else {
                throw error(method: "GET", path: path, response: response)
            }
            return try JSONDecoder().decode(Content.self, from: response.data).type
        }

        /// Reads one current Issue body and its HTTP entity tag. The tag and
        /// body digest are both required before an apply operation can begin.
        public func issueSnapshot(_ fullName: String, number: Int) async throws -> Issue.Snapshot {
            let path = "/repos/\(fullName)/issues/\(number)"
            let response = try await request(method: "GET", path: path)
            guard response.status == 200 else {
                throw error(method: "GET", path: path, response: response)
            }
            guard let revision = response.headers["Etag"] ?? response.headers["ETag"] else {
                throw ConfigurationError("\(fullName)#\(number): GitHub did not return an entity tag")
            }
            let issue = try JSONDecoder().decode(RemoteIssue.self, from: response.data)
            let state: Issue.NativeState
            if issue.state == "open" {
                state = .open
            } else if issue.stateReason == "not_planned" {
                state = .notPlanned
            } else if issue.stateReason == "duplicate" {
                state = .duplicate
            } else {
                state = .completed
            }
            return .init(
                coordinate: issue.htmlURL,
                revision: revision,
                body: issue.body ?? "",
                native: .init(state: state)
            )
        }

        /// Plans a compaction from one current body. `apply: false` is fully
        /// report-only. On apply, the current GET compares the caller's
        /// revision and digest immediately before the one body PATCH; GitHub
        /// does not support conditional unsafe REST requests. The checkpoint
        /// comment is posted only after that PATCH succeeds.
        public func compactIssue(
            _ fullName: String,
            number: Int,
            guard expected: Issue.Guard,
            apply: Bool
        ) async throws -> Issue.Compaction? {
            let snapshot = try await issueSnapshot(fullName, number: number)
            guard let plan = try Issue.Compactor.plan(snapshot: snapshot, guard: expected) else {
                return nil
            }
            guard apply else { return plan }

            let issuePath = "/repos/\(fullName)/issues/\(number)"
            let update = try await request(
                method: "PATCH",
                path: issuePath,
                body: try JSONEncoder().encode(["body": plan.body])
            )
            guard update.status == 200 else {
                throw error(method: "PATCH", path: issuePath, response: update)
            }
            let commentPath = "\(issuePath)/comments"
            let comment = try await request(
                method: "POST",
                path: commentPath,
                body: try JSONEncoder().encode(["body": plan.checkpoint])
            )
            guard comment.status == 201 else {
                throw error(method: "POST", path: commentPath, response: comment)
            }
            return plan
        }

        public func surfaceFiles(_ fullName: String) async throws -> [String: String] {
            var pending = [
                ".github/workflows",
                ".github/actions",
                ".github/ISSUE_TEMPLATE",
            ]
            var files = [String: String]()
            while let path = pending.popLast() {
                let response = try await request(
                    method: "GET",
                    path: "/repos/\(fullName)/contents/\(path)"
                )
                if response.status == 404 {
                    continue
                }
                guard response.status == 200 else {
                    throw error(
                        method: "GET",
                        path: "/repos/\(fullName)/contents/\(path)",
                        response: response
                    )
                }

                if let entries = try? JSONDecoder().decode([Content].self, from: response.data) {
                    for entry in entries.sorted(by: { $0.path < $1.path }).reversed() {
                        if entry.type == "dir" {
                            pending.append(entry.path)
                        } else if entry.type == "file", isGovernedSurface(path: entry.path) {
                            pending.append(entry.path)
                        }
                    }
                    continue
                }

                let content = try JSONDecoder().decode(Content.self, from: response.data)
                guard content.type == "file", isGovernedSurface(path: content.path) else {
                    continue
                }
                guard
                    content.encoding == "base64",
                    let encoded = content.content,
                    let data = Data(
                        base64Encoded: encoded,
                        options: .ignoreUnknownCharacters
                    ),
                    let source = String(data: data, encoding: .utf8)
                else {
                    throw ConfigurationError(
                        "\(fullName): could not decode governed file \(content.path)"
                    )
                }
                files[content.path] = source
            }
            return files
        }

        public func vulnerabilityReporting(
            _ fullName: String
        ) async throws -> VulnerabilityReporting {
            let path = "/repos/\(fullName)/private-vulnerability-reporting"
            let response = try await request(method: "GET", path: path)
            if response.status == 404 { return .disabled }
            guard response.status == 200 else {
                throw error(method: "GET", path: path, response: response)
            }
            let state = try JSONDecoder().decode(PrivateVulnerabilityReporting.self, from: response.data)
            return state.enabled ? .enabled : .disabled
        }

        public func enableVulnerabilityReporting(_ fullName: String) async throws {
            let path = "/repos/\(fullName)/private-vulnerability-reporting"
            let response = try await request(method: "PUT", path: path)
            guard response.status == 204 else {
                throw error(method: "PUT", path: path, response: response)
            }
        }

        private func request(
            method: String,
            path: String,
            body: Data? = nil
        ) async throws -> (data: Data, status: Int, headers: [String: String]) {
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
                preconditionFailure("Invalid GitHub API path: \(path)")
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("swift-institute-repository-policy", forHTTPHeaderField: "User-Agent")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } else if method == "PUT" {
                request.httpBody = Data()
                request.setValue("0", forHTTPHeaderField: "Content-Length")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, response.statusCode, response.allHeaderFields.reduce(into: [:]) {
                $0[String(describing: $1.key)] = String(describing: $1.value)
            })
        }

        private func error(
            method: String,
            path: String,
            response: (data: Data, status: Int, headers: [String: String])
        ) -> Error {
            Error(
                method: method,
                path: path,
                status: response.status,
                response: String(decoding: response.data.prefix(2_000), as: UTF8.self)
            )
        }

        private func isGovernedSurface(path: String) -> Bool {
            if path.hasPrefix(".github/ISSUE_TEMPLATE/") {
                return true
            }
            if path.hasPrefix(".github/workflows/") {
                return path.hasSuffix(".yml") || path.hasSuffix(".yaml")
            }
            if path.hasPrefix(".github/actions/") {
                return path.hasSuffix("/action.yml") || path.hasSuffix("/action.yaml")
            }
            return false
        }

        private struct Content: Decodable {
            let type: String
            let path: String
            let encoding: String?
            let content: String?
        }

        private struct RemoteIssue: Decodable {
            let body: String?
            let htmlURL: String
            let state: String
            let stateReason: String?

            enum CodingKeys: String, CodingKey {
                case body
                case htmlURL = "html_url"
                case state
                case stateReason = "state_reason"
            }
        }

        private struct PrivateVulnerabilityReporting: Decodable {
            let enabled: Bool
        }
    }
}
