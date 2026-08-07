import CI_Canon
import CI_Contract
import Foundation

extension CI.Validation {
    /// `[GH-IGNORE-001]` / `[GH-IGNORE-002]` — the canonical package
    /// `.gitignore`, and the work it must not deny.
    ///
    /// **001** is conformance: the file's canonical half must match
    /// `canon/gitignore-package.txt` byte-for-byte, and the file must
    /// have such a half. Content after the terminator is the package's
    /// own and is not compared.
    ///
    /// **002 is the half that matters.** A whitelist inverts the failure
    /// mode. Before it, junk crept in and `git status` showed you; after
    /// it, anything not explicitly allowed is untracked and `git status`
    /// says *nothing* — on 2026-07-29 a research paper in this ecosystem
    /// existed only as an untracked directory, one `git clean` from being
    /// lost. A validator that asks only "is junk denied?" would have
    /// reported that repository clean. This one also asks "is real work
    /// still tracked?", which is what makes work-loss loud. Do not weaken
    /// it to a warning, and when the whitelist gains a directory, add a
    /// probe for it here in the same change.
    ///
    /// Both halves evaluate the file **the way git will**: it is copied
    /// into a throwaway `git init` tree with the probe paths
    /// materialised, and `git check-ignore` decides. Reading the patterns
    /// and reasoning about them is how the premise of this gate came to
    /// be wrong in the first place — the absence of a `.swift-lint`
    /// deny-line was read as the absence of denial, when the whitelist
    /// was denying it all along.
    public struct Gitignore: Validator {
        /// A path the whitelist is probed with, and whether git must be
        /// told it is a directory.
        ///
        /// The directory bit is carried because a pattern with a trailing
        /// slash — `**/.*/` — never matches a path git does not know to
        /// be one.
        public struct Probe: Sendable, Equatable {
            public let path: String
            public let isDirectory: Bool

            public init(_ path: String, isDirectory: Bool = false) {
                self.path = path
                self.isDirectory = isDirectory
            }
        }

        /// Paths that carry real work. Every one must survive the
        /// whitelist.
        public static let work: [Probe] = [
            Probe("Sources/Core/Type.swift"),
            Probe("Sources/Core/Type.docc/Article.md"),
            Probe("Sources/Core/Type.docc/asset.png"),
            Probe("Tests/Core Tests/Type Tests.swift"),
            Probe("Tests/Core Tests/Fixtures/case.json"),
            Probe("Benchmarks/bench/main.swift"),
            Probe("Research/paper.md"),
            Probe("Experiments/probe/main.swift"),
            Probe("Package.swift"),
            Probe("Lint.swift"),
            Probe("README.md"),
            Probe("LICENSE.md"),
            Probe(".github/workflows/ci.yml"),
            Probe(".spi.yml"),
            Probe(".gitignore"),
        ]

        /// Paths that must be denied. Not a rule of its own — a positive
        /// control on the probe harness. If these come back tracked,
        /// `git check-ignore` is not being reached and every 002 pass in
        /// the run is vacuous, which is exactly the shape of green this
        /// ecosystem has been burned by.
        public static let junk: [Probe] = [
            Probe(".swift-lint/eval/Package.swift"),
            Probe("Sources/.swift-lint/manifest.json"),
            Probe(".build/debug/thing.o"),
        ]

        public let rules: [Rule] = ["GH-IGNORE-001", "GH-IGNORE-002"]
        public let retiredScript: String? = ".github/scripts/validate-gitignore.py"

        /// Canon's path within the control-plane checkout.
        public static let canonPath = "canon/gitignore-package.txt"

        /// Where canon lives. `nil` means *find it*: the working
        /// directory and each of its ancestors are searched for
        /// `canonPath`.
        ///
        /// The retired script resolved canon from its own location
        /// (`__file__/../../canon/…`), which a Swift executable cannot
        /// reproduce — a built binary is not in the checkout it validates,
        /// and under `swift test` it is not in one at all. Searching
        /// upward from the working directory answers the same question
        /// the same way for the harness, for `validate-gitignore.yml`, and
        /// for a developer running from anywhere inside the checkout.
        public let canon: String?

        public init(canon: String? = nil) {
            self.canon = canon
        }

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let path = canon ?? Self.resolvedCanonPath ?? Self.canonPath
            guard let canonText = Self.read(path) else {
                throw .missingSupportFile(path: path)
            }
            guard let canonical = CI.Canon.Gitignore(canonText).canonical else {
                throw .missingSupportFile(path: path)
            }
            // Packages only. A repository with no manifest is not what
            // this canon describes.
            guard Self.read(subject.path("Package.swift")) != nil else { return [] }

            let conformance = rules[0]
            let workLoss = rules[1]
            guard let text = Self.read(subject.path(".gitignore")) else {
                return [
                    Finding(
                        repository: subject.repository, rule: conformance,
                        message: "no .gitignore; the canonical whitelist is absent")
                ]
            }

            var findings: [Finding] = []
            switch CI.Canon.Gitignore(text).canonical {
            case .none:
                findings.append(
                    Finding(
                        repository: subject.repository, rule: conformance,
                        message: "no CANONICAL section; file predates the canonical whitelist"))
            case .some(let section) where section != canonical:
                findings.append(
                    Finding(
                        repository: subject.repository, rule: conformance,
                        message: "CANONICAL section diverges from canon/gitignore-package.txt"))
            case .some:
                break
            }

            // 002 evaluates the repository's ACTUAL file, canonical or
            // not — a divergent file that loses real work should say so
            // on its own terms, not only via 001.
            let ignored = try Self.ignored(under: text, probes: Self.work + Self.junk)
            for probe in Self.work where ignored.contains(probe.path) {
                findings.append(
                    Finding(
                        repository: subject.repository, rule: workLoss,
                        message: "whitelist denies real work: `\(probe.path)` "
                            + "would be silently untracked"))
            }
            let tracked = Self.junk.filter { !ignored.contains($0.path) }
            if !tracked.isEmpty {
                // The control failed. Reported as a finding rather than
                // passed: a harness that cannot detect denial makes every
                // clean 002 above vacuous.
                findings.append(
                    Finding(
                        repository: subject.repository, rule: workLoss,
                        message: "probe control failed — tool state not denied ("
                            + tracked.map { "`\($0.path)`" }.joined(separator: ", ")
                            + "); this run's whitelist verdicts are not evidence"))
            }
            return findings
        }
    }
}

extension CI.Validation.Gitignore {
    /// `canonPath` found by walking up from the working directory, or
    /// `nil` when no ancestor carries it.
    static var resolvedCanonPath: String? {
        var directory = FileManager.default.currentDirectoryPath
        while !directory.isEmpty, directory != "/" {
            let candidate = "\(directory)/\(canonPath)"
            if read(candidate) != nil { return candidate }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// The text of a file, or `nil` when it is absent or is not a file.
    static func read(_ path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue,
            let data = FileManager.default.contents(atPath: path)
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Which probes the given `.gitignore` ignores, asked of git itself
    /// in a throwaway tree.
    ///
    /// - Throws: `EnvironmentDefect.missingSupportFile` when git cannot
    ///   be run or answers with neither of its two verdicts. The retired
    ///   script reported that as a `[GH-IGNORE-002]` *finding*, which
    ///   said a repository was defective when the machine was; under this
    ///   contract an unanswerable question is the exit-2 class. This is a
    ///   deliberate difference and it is unreachable on a working runner.
    static func ignored(
        under gitignore: String, probes: [Probe]
    ) throws(CI.Validation.EnvironmentDefect) -> Set<String> {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ci-validation-gitignore-\(UUID().uuidString)")
        // swift-linter:disable:next try optional
        // REASON: `FileManager.removeItem(at:)` throws untyped, and a
        // scratch tree that outlives the probe is not a verdict about
        // anything.
        defer { try? FileManager.default.removeItem(at: root) }

        for probe in probes {
            let target = root.appending(path: probe.path)
            let directory = probe.isDirectory ? target : target.deletingLastPathComponent()
            // swift-linter:disable:next try optional
            // REASON: `FileManager.createDirectory` throws untyped; its
            // failure here is the defect raised on the next line.
            let made = try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            guard made != nil else { throw .unreadableSubject(root: root.path) }
            if !probe.isDirectory {
                FileManager.default.createFile(atPath: target.path, contents: Data())
            }
        }
        // LAST, and deliberately so: `.gitignore` is itself a probe —
        // the file must not ignore itself — and materialising probes
        // as empty files would otherwise truncate the very file under
        // test. Every verdict in the run would then reflect an empty
        // ignore file, so all junk reads as tracked and all work
        // reads as kept. The junk control caught exactly this.
        // swift-linter:disable:next try optional
        // REASON: `Data.write(to:options:)` throws untyped; its failure
        // here is the defect raised on the next line.
        let written = try? Data(gitignore.utf8).write(
            to: root.appending(path: ".gitignore"), options: .atomic)
        guard written != nil else { throw .unreadableSubject(root: root.path) }

        guard try git(["init", "-q", "."], in: root) == 0 else {
            throw .missingSupportFile(path: "git init")
        }
        var ignored: Set<String> = []
        for probe in probes {
            // 0 = ignored, 1 = not ignored, >1 = git itself failed.
            let status = try git(["check-ignore", "-q", "--", probe.path], in: root)
            guard status <= 1 else {
                throw .missingSupportFile(path: "git check-ignore \(probe.path)")
            }
            if status == 0 { ignored.insert(probe.path) }
        }
        return ignored
    }

    /// One `git` invocation in the throwaway tree, returning its status.
    private static func git(
        _ arguments: [String], in root: URL
    ) throws(CI.Validation.EnvironmentDefect) -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // swift-linter:disable:next try optional
        // REASON: `Process.run()` is an untyped cross-module throw; there
        // is no typed spelling of it, and its only failure here is "git
        // is not on this machine", which is the defect below.
        guard (try? process.run()) != nil else {
            throw .missingSupportFile(path: "git")
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
