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

    /// Initializes a git repository at `root` (idempotent) and commits
    /// every file already written into it, returning the commit's SHA.
    ///
    /// `[CI-118]`'s `PinnedContent` resolves a pinned action's schema by
    /// git object access at an exact commit, never the working tree --
    /// so a fixture that exercises real resolution (rather than only the
    /// unreachable/fail-closed path) needs an actual git history to
    /// resolve against, not just files on disk. This gives fixtures one.
    @discardableResult
    func gitCommit() -> String {
        Self.run(["git", "init", "-q", root])
        Self.run(["git", "-C", root, "config", "user.email", "fixture@example.invalid"])
        Self.run(["git", "-C", root, "config", "user.name", "fixture"])
        Self.run(["git", "-C", root, "add", "-A"])
        Self.run(["git", "-C", root, "commit", "-q", "--allow-empty", "-m", "fixture"])
        return Self.run(["git", "-C", root, "rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pipe creation and `Process.run()` are serialized through
    /// `CI.Validation.PinnedContent.spawning` -- the same queue the
    /// production subprocess runner uses -- because a child forked by
    /// ANY spawner in this process while another spawner's pipe write
    /// ends are momentarily open in the parent inherits those
    /// descriptors and starves the sibling's drain of its EOF. Swift
    /// Testing runs suites in parallel, so fixture git spawns and
    /// production git spawns genuinely overlap.
    @discardableResult
    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let pipe = CI.Validation.PinnedContent.spawning.sync {
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            return pipe
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }
}
