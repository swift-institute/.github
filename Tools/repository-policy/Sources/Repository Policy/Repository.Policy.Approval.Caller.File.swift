import Foundation

extension Repository.Policy.Approval.Caller {
    public struct File: Sendable, Equatable {
        public let revision: String
        public let contents: Data

        public init(revision: String, contents: Data) {
            self.revision = revision
            self.contents = contents
        }
    }
}
