import GitHub

extension GitHub.Control {
    /// A Package URL for a SwiftPM dependency.
    ///
    /// `pkg:swift/<host>/<owner>/<repo>[@<version>]`, per the purl
    /// spec's swift type. The version is the resolved git ref — a tag
    /// where the dependency is tag-pinned, a commit SHA under the
    /// Institute's branch-main pinning convention.
    public struct PackageURL: Sendable, Equatable, CustomStringConvertible {
        public let host: String
        public let path: String
        public let version: String

        public init(host: String, path: String, version: String) {
            self.host = host
            self.path = path
            self.version = version
        }

        /// Derive a purl from a dependency's git URL.
        ///
        /// A URL with no host reads as `github.com`: SwiftPM accepts
        /// scp-style and relative spellings, and the Institute's
        /// dependencies are all GitHub-hosted, so defaulting keeps a
        /// dependency in the snapshot rather than dropping it silently.
        public init(gitURL: String, version: String) {
            var text = gitURL
            while text.hasSuffix("/") { text.removeLast() }
            var host = "github.com"
            var path = text
            if let separator = text.range(of: "://") {
                let remainder = text[separator.upperBound...]
                let split = remainder.firstIndex(of: "/") ?? remainder.endIndex
                let authority = String(remainder[remainder.startIndex..<split])
                if !authority.isEmpty { host = authority }
                path = String(remainder[split...])
            }
            while path.hasPrefix("/") { path.removeFirst() }
            if path.hasSuffix(".git") { path.removeLast(4) }
            self.init(host: host, path: path, version: version)
        }

        public var description: String {
            let name = "pkg:swift/\(host)/\(path)"
            return version.isEmpty ? name : name + "@" + version
        }
    }
}
