import Foundation

extension RepositoryPolicy.GitHubClient {
    public func caller(
        for fullName: String,
        path callerPath: String
    ) async throws -> Repository.Policy.Approval.Caller.State {
        let repositoryPath = "/repos/\(fullName)"
        let repositoryResponse = try await request(method: "GET", path: repositoryPath)
        guard repositoryResponse.status == 200 else {
            throw error(
                method: "GET",
                path: repositoryPath,
                response: repositoryResponse
            )
        }
        let repository = try JSONDecoder().decode(
            Repository.Policy.Approval.Caller.Remote.self,
            from: repositoryResponse.data
        )
        let file = try await approvalCallerFile(
            in: fullName,
            path: callerPath,
            ref: repository.defaultBranch
        )
        return .init(
            visibility: repository.visibility,
            archived: repository.archived,
            branch: repository.defaultBranch,
            file: file
        )
    }

    /// Creates or resumes one deterministic, single-file proposal branch and
    /// opens a pull request. The default branch is never mutated directly.
    /// Returns true only when this invocation created the pull request.
    public func proposeCaller(
        at callerPath: String,
        in fullName: String,
        base: String,
        revision: String?,
        contents: Data
    ) async throws -> Bool {
        guard let owner = fullName.split(separator: "/", omittingEmptySubsequences: false).first,
            !owner.isEmpty
        else {
            throw RepositoryPolicy.ConfigurationError("approval caller target is invalid")
        }
        guard let baseHead = try await approvalCallerReference(in: fullName, branch: base) else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller default branch has no Git reference"
            )
        }
        let proposal = "bot/483-private-review-caller-\(baseHead.prefix(12))"
        let managedPrefix = "bot/483-private-review-caller-"
        let open = try await approvalCallerPulls(
            path: "/repos/\(fullName)/pulls?state=open&per_page=100"
        )
        let managed = open.filter { $0.head.ref.hasPrefix(managedPrefix) }
        guard open.count < 100,
            managed.count <= 1,
            managed.allSatisfy({ $0.head.ref == proposal && $0.base.ref == base })
        else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller already has an ambiguous or stale managed pull request"
            )
        }
        let existingProposal = try await approvalCallerReference(in: fullName, branch: proposal)
        if existingProposal == nil {
            let referencePath = "/repos/\(fullName)/git/refs"
            let response = try await request(
                method: "POST",
                path: referencePath,
                body: try JSONEncoder().encode(
                    Repository.Policy.Approval.Caller.CreateReference(
                        ref: "refs/heads/\(proposal)",
                        sha: baseHead
                    )
                )
            )
            guard response.status == 201 else {
                throw error(method: "POST", path: referencePath, response: response)
            }
        }

        let proposalFile = try await approvalCallerFile(
            in: fullName,
            path: callerPath,
            ref: proposal
        )
        if proposalFile?.contents != contents {
            let proposalHead = try await approvalCallerReference(in: fullName, branch: proposal)
            guard proposalHead == baseHead else {
                throw RepositoryPolicy.ConfigurationError(
                    "approval caller proposal branch is not the guarded default head"
                )
            }
            let path = "/repos/\(fullName)/contents/\(callerPath)"
            let payload = Repository.Policy.Approval.Caller.Update(
                message: "Propose canonical private review caller",
                content: contents.base64EncodedString(),
                branch: proposal,
                sha: revision
            )
            let response = try await request(
                method: "PUT",
                path: path,
                body: try JSONEncoder().encode(payload)
            )
            guard response.status == 200 || response.status == 201 else {
                throw error(method: "PUT", path: path, response: response)
            }
        }

        guard
            try await approvalCallerFile(in: fullName, path: callerPath, ref: proposal)?.contents
                == contents,
            let proposalHead = try await approvalCallerReference(in: fullName, branch: proposal)
        else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller proposal did not preserve canonical bytes"
            )
        }
        let comparePath = "/repos/\(fullName)/compare/\(baseHead)...\(proposalHead)"
        let compareResponse = try await request(method: "GET", path: comparePath)
        guard compareResponse.status == 200 else {
            throw error(method: "GET", path: comparePath, response: compareResponse)
        }
        let comparison = try JSONDecoder().decode(
            Repository.Policy.Approval.Caller.Comparison.self,
            from: compareResponse.data
        )
        guard comparison.status == "ahead",
            comparison.aheadBy == 1,
            comparison.behindBy == 0,
            comparison.files.map(\.filename) == [callerPath]
        else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller proposal is not one guarded single-file commit"
            )
        }

        let encodedHead = try approvalCallerQuery("\(owner):\(proposal)")
        let encodedBase = try approvalCallerQuery(base)
        let pullsPath =
            "/repos/\(fullName)/pulls?state=open&head=\(encodedHead)&base=\(encodedBase)&per_page=100"
        var pulls = try await approvalCallerPulls(path: pullsPath)
        guard pulls.count <= 1 else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller proposal has ambiguous open pull requests"
            )
        }
        var created = false
        if pulls.isEmpty {
            let createPath = "/repos/\(fullName)/pulls"
            let response = try await request(
                method: "POST",
                path: createPath,
                body: try JSONEncoder().encode(
                    Repository.Policy.Approval.Caller.CreatePull(
                        title: "Converge private review caller",
                        body: """
                            Proposes the canonical private exact-head review caller.

                            Durable owner: swift-institute/.github#483.
                            This proposal is not merge authorization.
                            """,
                        head: proposal,
                        base: base
                    )
                )
            )
            guard response.status == 201 else {
                throw error(method: "POST", path: createPath, response: response)
            }
            created = true
            pulls = try await approvalCallerPulls(path: pullsPath)
        }
        guard pulls.count == 1,
            let pull = pulls.first,
            pull.number > 0,
            pull.state == "open",
            pull.head.ref == proposal,
            pull.head.sha == proposalHead,
            pull.base.ref == base,
            try await approvalCallerReference(in: fullName, branch: proposal) == proposalHead
        else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller pull-request readback did not match its guarded proposal"
            )
        }
        return created
    }

    private func approvalCallerFile(
        in fullName: String,
        path callerPath: String,
        ref: String
    ) async throws -> Repository.Policy.Approval.Caller.File? {
        let encodedRef = try approvalCallerQuery(ref)
        let contentPath = "/repos/\(fullName)/contents/\(callerPath)?ref=\(encodedRef)"
        let contentResponse = try await request(method: "GET", path: contentPath)
        if contentResponse.status == 404 { return nil }
        guard contentResponse.status == 200 else {
            throw error(method: "GET", path: contentPath, response: contentResponse)
        }
        let content = try JSONDecoder().decode(
            Repository.Policy.Approval.Caller.Content.self,
            from: contentResponse.data
        )
        guard content.encoding == "base64",
            let encoded = content.content,
            let revision = content.sha,
            let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        else {
            throw RepositoryPolicy.ConfigurationError(
                "approval caller contents could not be decoded"
            )
        }
        return .init(revision: revision, contents: data)
    }

    private func approvalCallerReference(
        in fullName: String,
        branch: String
    ) async throws -> String? {
        let path = "/repos/\(fullName)/git/ref/heads/\(branch)"
        let response = try await request(method: "GET", path: path)
        if response.status == 404 { return nil }
        guard response.status == 200 else {
            throw error(method: "GET", path: path, response: response)
        }
        return try JSONDecoder().decode(
            Repository.Policy.Approval.Caller.Reference.self,
            from: response.data
        ).object.sha
    }

    private func approvalCallerPulls(
        path: String
    ) async throws -> [Repository.Policy.Approval.Caller.Pull] {
        let response = try await request(method: "GET", path: path)
        guard response.status == 200 else {
            throw error(method: "GET", path: path, response: response)
        }
        return try JSONDecoder().decode(
            [Repository.Policy.Approval.Caller.Pull].self,
            from: response.data
        )
    }

    private func approvalCallerQuery(_ value: String) throws -> String {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else {
            throw RepositoryPolicy.ConfigurationError("approval caller query could not be encoded")
        }
        return encoded
    }
}
