import GitHub
import GitHub_HTTP

extension GitHub.Control {
    /// The control plane's client composition: a canonical
    /// `GitHub.HTTP.Client` bound to a step-scoped `AppCredential`, with
    /// this package's retry policy and complete pagination. The transport
    /// `execute` closure is injected by the composition root
    /// (institute-ci-control); this type owns no socket and no policy
    /// beyond what its parts declare.
    public struct Client<ExecutionFailure: Swift.Error>: Sendable {
        public let credential: AppCredential
        public let retryPolicy: RetryPolicy
        public let http: GitHub.HTTP.Client<ExecutionFailure, GitHub.HTTP.Pagination.Error>

        public init(
            credential: AppCredential,
            retryPolicy: RetryPolicy = RetryPolicy(),
            execute: @escaping @Sendable (HTTP.Request) async throws(ExecutionFailure) -> HTTP.Response
        ) {
            self.credential = credential
            self.retryPolicy = retryPolicy
            self.http = GitHub.HTTP.Client(
                agent: .init(rawValue: "institute-ci-control"),
                version: .init(rawValue: "2022-11-28"),
                execute: execute,
                pagination: .link)
        }
    }
}
