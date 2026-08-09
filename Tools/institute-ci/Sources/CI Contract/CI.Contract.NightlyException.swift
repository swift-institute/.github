extension CI.Contract {
    /// A temporary, external-defect classification for the Swift main nightly.
    ///
    /// Nightly is never advisory merely because it is nightly: the exact image,
    /// upstream defect, and recheck date must all be recorded and valid.
    public struct NightlyException: Sendable, Equatable {
        public enum Error: Swift.Error, Equatable {
            case image(String)
            case upstreamIssue(String)
            case recheck(String)
            case expired(recheck: String, today: String)
        }

        public let image: String
        public let upstreamIssue: String
        public let recheck: String

        public init(image: String, upstreamIssue: String, recheck: String) {
            self.image = image
            self.upstreamIssue = upstreamIssue
            self.recheck = recheck
        }

        public func validate(today: String) throws(Error) {
            let prefix = "swiftlang/swift@sha256:"
            let digest = String(image.dropFirst(prefix.count))
            guard image.hasPrefix(prefix), digest.count == 64,
                  digest.allSatisfy(\.isHexDigit)
            else { throw .image(image) }
            let issuePrefix = "https://github.com/swiftlang/swift/issues/"
            let issue = String(upstreamIssue.dropFirst(issuePrefix.count))
            guard upstreamIssue.hasPrefix(issuePrefix), !issue.isEmpty,
                  issue.allSatisfy(\.isNumber)
            else { throw .upstreamIssue(upstreamIssue) }
            guard Self.isDate(recheck), Self.isDate(today)
            else { throw .recheck(recheck) }
            guard today <= recheck else { throw .expired(recheck: recheck, today: today) }
        }

        static func isDate(_ text: String) -> Bool {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            return parts.count == 3
                && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
                && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
        }
    }
}
