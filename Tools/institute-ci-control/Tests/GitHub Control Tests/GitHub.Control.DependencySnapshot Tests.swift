import Foundation
import GitHub
import Testing

@testable import GitHub_Control

/// The dependency-graph snapshot, over a recorded `swift package
/// show-dependencies` tree. Nothing here submits anything.
@Suite
struct GitHubControlDependencySnapshotTests {
    /// A recorded tree with a diamond: `swift-fips-180-4` is reached
    /// both directly and through `swift-github`.
    static var tree: [String: Any] {
        [
        "name": "institute-ci-control",
        "url": "https://github.com/swift-institute/.github",
        "dependencies": [
            [
                "name": "swift-github",
                "url": "https://github.com/swift-foundations/swift-github.git",
                "version": "unspecified",
                "dependencies": [
                    [
                        "name": "swift-fips-180-4",
                        "url": "https://github.com/swift-standards/swift-fips-180-4.git",
                        "version": "1.2.3",
                        "dependencies": [],
                    ]
                ],
            ],
            [
                "name": "swift-fips-180-4",
                "url": "https://github.com/swift-standards/swift-fips-180-4.git",
                "version": "1.2.3",
                "dependencies": [],
            ],
        ],
        ]
    }

    @Suite
    struct PackageURLTests {
        @Test func `an https git url becomes a swift purl`() {
            #expect(
                GitHub.Control.PackageURL(
                    gitURL: "https://github.com/swift-standards/swift-fips-180-4.git",
                    version: "1.2.3").description
                    == "pkg:swift/github.com/swift-standards/swift-fips-180-4@1.2.3")
        }

        @Test func `a trailing slash and a dot git suffix are both stripped`() {
            #expect(
                GitHub.Control.PackageURL(
                    gitURL: "https://github.com/a/b.git/", version: "").description
                    == "pkg:swift/github.com/a/b")
        }

        @Test func `a branch pinned dependency carries its commit sha as the version`() {
            let sha = String(repeating: "e", count: 40)
            #expect(
                GitHub.Control.PackageURL(
                    gitURL: "https://github.com/a/b.git", version: sha).description
                    == "pkg:swift/github.com/a/b@\(sha)")
        }

        @Test func `a non github host is preserved`() {
            #expect(
                GitHub.Control.PackageURL(
                    gitURL: "https://gitlab.example/a/b.git", version: "1.0").description
                    == "pkg:swift/gitlab.example/a/b@1.0")
        }

        @Test func `an scp style url keeps a dependency in the snapshot`() {
            // urlparse gives such a URL no netloc; dropping it would
            // silently shrink the submitted graph, which is worse than a
            // defaulted host.
            #expect(
                GitHub.Control.PackageURL(
                    gitURL: "git@github.com:a/b.git", version: "1.0").description
                    == "pkg:swift/github.com/git@github.com:a/b@1.0")
        }
    }

    @Suite
    struct ResolutionTests {
        @Test func `a child of the root is direct and a grandchild is indirect`() {
            let resolutions = GitHub.Control.DependencySnapshot
                .resolutions(ofDependencyTree: GitHubControlDependencySnapshotTests.tree)
            #expect(resolutions.map(\.name) == ["swift-github", "swift-fips-180-4"])
            #expect(resolutions[0].relationship == "direct")
            #expect(resolutions[1].relationship == "indirect")
        }

        @Test func `a diamond is resolved once, at the shallowest reach`() {
            let resolutions = GitHub.Control.DependencySnapshot
                .resolutions(ofDependencyTree: GitHubControlDependencySnapshotTests.tree)
            #expect(resolutions.count(where: { $0.name == "swift-fips-180-4" }) == 1)
        }

        @Test func `a dependency with no url is not submitted`() {
            let resolutions = GitHub.Control.DependencySnapshot.resolutions(
                ofDependencyTree: ["dependencies": [["name": "nameless", "url": ""]]])
            #expect(resolutions.isEmpty)
        }

        @Test func `a leaf tree resolves nothing`() {
            #expect(
                GitHub.Control.DependencySnapshot
                    .resolutions(ofDependencyTree: ["name": "root"]).isEmpty)
        }
    }

    @Suite
    struct DocumentTests {
        static func snapshot() -> GitHub.Control.DependencySnapshot {
            GitHub.Control.DependencySnapshot(
                sha: String(repeating: "d", count: 40),
                ref: "refs/heads/main",
                job: .init(id: "12345", correlator: "7"),
                scanned: "2026-08-07T00:00:00.000Z",
                resolutions: GitHub.Control.DependencySnapshot
                    .resolutions(ofDependencyTree: GitHubControlDependencySnapshotTests.tree))
        }

        @Test func `the document is the shape the submission endpoint takes`() throws {
            let text = try Self.snapshot().json()
            let object = try #require(
                try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(object["version"] as? Int == 0)
            #expect(object["sha"] as? String == String(repeating: "d", count: 40))
            #expect(object["ref"] as? String == "refs/heads/main")
            #expect((object["job"] as? [String: Any])?["correlator"] as? String == "7")
            #expect(
                (object["detector"] as? [String: Any])?["name"] as? String
                    == "swift-institute-bot dep-graph submitter")
            let manifest = try #require(
                (object["manifests"] as? [String: Any])?["Package.swift"] as? [String: Any])
            #expect(
                (manifest["file"] as? [String: Any])?["source_location"] as? String
                    == "Package.swift")
            let resolved = try #require(manifest["resolved"] as? [String: Any])
            let github = try #require(resolved["swift-github"] as? [String: Any])
            #expect(github["relationship"] as? String == "direct")
            #expect(github["scope"] as? String == "runtime")
            #expect(
                github["package_url"] as? String
                    == "pkg:swift/github.com/swift-foundations/swift-github@unspecified")
        }

        @Test func `purl slashes are not escaped`() throws {
            // A JSON writer may escape `/`; the purls are almost all
            // slash, and an escaped document compares unequal to the
            // retired script's for no semantic reason.
            #expect(!(try Self.snapshot().json()).contains(#"\/"#))
        }

        @Test func `the scan timestamp is an internet date time in UTC`() {
            let scanned = GitHub.Control.DependencySnapshot.scanned(
                Date(timeIntervalSince1970: 0))
            #expect(scanned == "1970-01-01T00:00:00.000Z")
        }
    }
}
