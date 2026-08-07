import CI_Contract
import Foundation

@testable import CI_Validation

/// The checkout these tests are running inside.
///
/// Two controls need the real tree rather than a synthetic shape: the
/// organization manifest `[BRANCH-PIN-001]` is scoped by, and the
/// corrigendum's mandatory `[CI-117]` assertion that every committed
/// self-referential reference is already identity-pinned. Both are
/// answered by locating one canonical file from this source file's own
/// path, so neither depends on the working directory a test runner
/// happens to use.
enum RepositoryUnderTest {
    /// `<root>/.github/actions/read-orgs/orgs.yaml`.
    static let organizationsFile: String = {
        guard
            let path = CI.Validation.BranchPins.Organizations.locateManifest(
                startingAt: (#filePath as NSString).deletingLastPathComponent
            )
        else { fatalError("orgs manifest not found above \(#filePath)") }
        return path
    }()

    /// The checkout root — the manifest path with its four known
    /// components removed.
    static let root: String = {
        var path = organizationsFile as NSString
        for _ in 0..<4 { path = path.deletingLastPathComponent as NSString }
        return path as String
    }()

    static var subject: CI.Validation.Subject {
        CI.Validation.Subject(repository: "swift-institute/.github", root: root)
    }
}

/// A throwaway repository-shaped directory a validator can be asked
/// about.
///
/// The fixture corpus under `.github/scripts/tests/fixtures/` is the
/// contract's shared corpus and is **data** — it is read, never written.
/// A control that needs a shape the corpus does not carry (a baseline
/// ledger, a deliberately unpinned reference) builds it here instead of
/// adding to the corpus, so the differential gate keeps comparing two
/// implementations over identical bytes.
struct TemporaryRepository: ~Copyable {
    let repository: String
    let root: String

    init(repository: String = "swift-institute-test/fixture") {
        self.repository = repository
        self.root = NSTemporaryDirectory() + "institute-ci-tests/" + UUID().uuidString
        try? FileManager.default.createDirectory(
            atPath: root,
            withIntermediateDirectories: true
        )
    }

    var subject: CI.Validation.Subject {
        CI.Validation.Subject(repository: repository, root: root)
    }

    /// Write `contents` at a path relative to the root, creating
    /// intermediate directories.
    func write(_ contents: String, to relative: String) {
        let path = root + "/" + relative
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? Data(contents.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// The absolute path of a file written into this repository.
    func path(_ relative: String) -> String { root + "/" + relative }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }
}
