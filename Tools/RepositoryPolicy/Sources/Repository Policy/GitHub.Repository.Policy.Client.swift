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
            path: String
        ) async throws -> (data: Data, status: Int) {
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
                preconditionFailure("Invalid GitHub API path: \(path)")
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("swift-institute-repository-policy", forHTTPHeaderField: "User-Agent")
            if method == "PUT" {
                request.httpBody = Data()
                request.setValue("0", forHTTPHeaderField: "Content-Length")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, response.statusCode)
        }

        private func error(
            method: String,
            path: String,
            response: (data: Data, status: Int)
        ) -> Error {
            Error(
                method: method,
                path: path,
                status: response.status,
                response: String(decoding: response.data.prefix(2_000), as: UTF8.self)
            )
        }

        private struct Content: Decodable {
            let type: String
        }

        private struct PrivateVulnerabilityReporting: Decodable {
            let enabled: Bool
        }
    }
}
