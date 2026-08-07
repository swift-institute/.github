import Foundation
import GitHub

extension GitHub.Control {
    /// A dependency-graph snapshot, as
    /// `POST /repos/{owner}/{repo}/dependency-graph/snapshots` takes it.
    ///
    /// Built from `swift package show-dependencies --format json`. The
    /// submission itself is a credentialed call the caller makes; this
    /// type owns only the document, which is why it can be proved
    /// against a recorded dependency tree with no token in sight.
    public struct DependencySnapshot: Sendable, Equatable {
        /// One resolved dependency in the snapshot's single manifest.
        public struct Resolution: Sendable, Equatable {
            public let name: String
            public let packageURL: PackageURL
            public let isDirect: Bool

            public init(name: String, packageURL: PackageURL, isDirect: Bool) {
                self.name = name
                self.packageURL = packageURL
                self.isDirect = isDirect
            }

            public var relationship: String { isDirect ? "direct" : "indirect" }
        }

        /// The submitting job, as the API correlates submissions.
        public struct Job: Sendable, Equatable {
            public let id: String
            public let correlator: String

            public init(id: String, correlator: String) {
                self.id = id
                self.correlator = correlator
            }
        }

        public static let detectorName = "swift-institute-bot dep-graph submitter"
        public static let detectorURL = "https://github.com/swift-institute/.github"
        public static let detectorVersion = "0.1.0"

        public let sha: String
        public let ref: String
        public let job: Job
        public let scanned: String
        public let resolutions: [Resolution]

        public init(
            sha: String, ref: String, job: Job, scanned: String,
            resolutions: [Resolution]
        ) {
            self.sha = sha
            self.ref = ref
            self.job = job
            self.scanned = scanned
            self.resolutions = resolutions
        }

        /// Flatten a `show-dependencies` tree into the snapshot's
        /// resolutions.
        ///
        /// Direct means a child of the root. Deduplication is by package
        /// name across the whole walk, so a diamond appears once — the
        /// API rejects a manifest that resolves one name twice, and the
        /// first occurrence is the shallowest, which is also the one
        /// whose relationship is right.
        public static func resolutions(
            ofDependencyTree root: [String: Any]
        ) -> [Resolution] {
            var seen: Set<String> = []
            var resolutions: [Resolution] = []

            func walk(_ node: [String: Any], depth: Int) {
                guard let children = node["dependencies"] as? [[String: Any]] else { return }
                for child in children {
                    let name = child["name"] as? String ?? ""
                    guard seen.insert(name).inserted else { continue }
                    let url = child["url"] as? String ?? ""
                    if !name.isEmpty, !url.isEmpty {
                        resolutions.append(
                            Resolution(
                                name: name,
                                packageURL: PackageURL(
                                    gitURL: url, version: child["version"] as? String ?? ""),
                                isDirect: depth == 0))
                    }
                    walk(child, depth: depth + 1)
                }
            }
            walk(root, depth: 0)
            return resolutions
        }

        /// The snapshot document.
        ///
        /// Keys are sorted and slashes are left unescaped: the document
        /// is compared against the retired script's output, and both of
        /// those are places where two JSON writers disagree without
        /// disagreeing about the document.
        public func json() throws -> String {
            var resolved: [String: Any] = [:]
            for resolution in resolutions {
                resolved[resolution.name] = [
                    "package_url": resolution.packageURL.description,
                    "relationship": resolution.relationship,
                    "scope": "runtime",
                ]
            }
            let document: [String: Any] = [
                "version": 0,
                "sha": sha,
                "ref": ref,
                "job": ["id": job.id, "correlator": job.correlator],
                "detector": [
                    "name": Self.detectorName,
                    "url": Self.detectorURL,
                    "version": Self.detectorVersion,
                ],
                "scanned": scanned,
                "manifests": [
                    "Package.swift": [
                        "name": "Package.swift",
                        "file": ["source_location": "Package.swift"],
                        "resolved": resolved,
                    ]
                ],
            ]
            let data = try JSONSerialization.data(
                withJSONObject: document,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }

        /// The scan timestamp, in the API's expected spelling.
        public static func scanned(_ instant: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: instant)
        }
    }
}
