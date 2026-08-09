import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// Resolves a same-repo/local pinned composite action's declared
    /// `inputs:`/`outputs:` schema at the exact commit a `uses:` line
    /// pins to, via git object access against the checkout the
    /// validator runs inside -- never the working tree, so a call site
    /// pinned to an OLDER or NEWER commit than what happens to be
    /// checked out is still answered against the revision it actually
    /// names.
    ///
    /// FAILS CLOSED. An unreachable or unfetchable pinned object is a
    /// `.unreachable` resolution and every consumer must turn that into
    /// a finding, never a silent skip -- the whole point of resolving
    /// against the pin rather than the working tree is that "I could not
    /// check" and "I checked and it was fine" must not collapse into the
    /// same silence.
    ///
    /// `[CI-117]` (`CompositeActionPins`) verifies only that a
    /// self-referential `uses:` ref is a full 40-hex identity pin; it is
    /// unrelated to and untouched by this component, and is a candidate
    /// future consumer of it (to resolve the pinned blob it currently
    /// only regex-matches the ref text of) rather than re-deriving git
    /// access of its own.
    public enum PinnedContent {
        /// A same-repo/local composite action's directory (repository-
        /// root-relative, no leading `./`) and the 40-hex commit SHA a
        /// `uses:` line pins it to.
        public struct Coordinate: Sendable, Equatable {
            public let path: String
            public let sha: String

            public init(path: String, sha: String) {
                self.path = path
                self.sha = sha
            }
        }

        /// An action's declared `inputs:`/`outputs:` key sets, as of one
        /// pinned commit.
        public struct Schema: Sendable, Equatable {
            public let inputs: Set<String>
            public let outputs: Set<String>

            public init(inputs: Set<String>, outputs: Set<String>) {
                self.inputs = inputs
                self.outputs = outputs
            }
        }

        /// What resolving a `Coordinate` produced.
        public enum Resolution: Sendable, Equatable {
            /// The pinned `action.yml` was read at its exact commit and
            /// parsed.
            case resolved(Schema)

            /// The pinned object could not be read -- the commit is
            /// unreachable in this checkout's git history, the path does
            /// not exist at that commit, or the blob did not parse as
            /// YAML. This is itself a violation for a fail-closed
            /// consumer, never a reason to skip the call site.
            case unreachable(reason: String)
        }

        /// `<referencePrefix><name>@<40-hex-sha>` -> `Coordinate`, or
        /// `nil` when `uses` is not a same-repo pinned composite-action
        /// reference: a third-party action, a reusable workflow, or an
        /// unpinned/floating ref (that shape is `[CI-117]`'s business,
        /// not this component's -- an unpinned ref has no exact commit
        /// to resolve against).
        public static func coordinate(uses: String, referencePrefix: String) -> Coordinate? {
            guard uses.hasPrefix(referencePrefix) else { return nil }
            let rest = uses.dropFirst(referencePrefix.count)
            guard let at = rest.lastIndex(of: "@") else { return nil }
            let name = rest[rest.startIndex..<at]
            let sha = rest[rest.index(after: at)...]
            guard !name.isEmpty, Self.isFullSHA(sha) else { return nil }
            return Coordinate(path: ".github/actions/\(name)", sha: String(sha))
        }

        static func isFullSHA(_ value: some StringProtocol) -> Bool {
            value.count == 40
                && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
        }

        /// Resolves `coordinate`'s `action.yml` via
        /// `git cat-file -p <sha>:<path>/action.yml` run against
        /// `gitRoot`, then parses its `inputs:`/`outputs:` blocks with
        /// the same bounded YAML reader `CI.Workflow.Document` uses.
        ///
        /// A `gitRoot` that is a SHALLOW checkout (CI's
        /// `tools-tests.yml` runs with `fetch-depth: 1`) can have a
        /// perfectly valid pinned commit simply absent from local git
        /// object storage -- "not fetched yet" is not "does not
        /// exist". When the first `cat-file` fails AND the checkout is
        /// shallow, this makes one targeted `git fetch --depth 1
        /// <remote> <sha>` attempt and retries before concluding
        /// anything. Only a fetch that itself fails (or a retry that
        /// still can't read the object) is reported `.unreachable` --
        /// an honestly-absent or bogus pin is still a violation exactly
        /// as before; this only stops a shallow-but-fetchable pin from
        /// falsely firing.
        public static func resolve(_ coordinate: Coordinate, gitRoot: String) -> Resolution {
            let object = "\(coordinate.sha):\(coordinate.path)/action.yml"
            switch Self.run(["git", "-C", gitRoot, "cat-file", "-p", object]) {
            case .success(let text):
                return Self.parsed(text, object: object)

            case .failure(let reason):
                guard Self.isShallowRepository(gitRoot: gitRoot) else {
                    return .unreachable(reason: "git cat-file \(object) failed: \(reason)")
                }
                switch Self.fetch(coordinate.sha, gitRoot: gitRoot) {
                case .failure(let fetchReason):
                    return .unreachable(
                        reason: "git cat-file \(object) failed: \(reason); this is a shallow "
                            + "repository and fetching \(coordinate.sha) also failed: "
                            + "\(fetchReason)")
                case .success:
                    switch Self.run(["git", "-C", gitRoot, "cat-file", "-p", object]) {
                    case .success(let text):
                        return Self.parsed(text, object: object)
                    case .failure(let retryReason):
                        return .unreachable(
                            reason: "git cat-file \(object) still failed after fetching "
                                + "\(coordinate.sha) into this shallow repository: "
                                + "\(retryReason)")
                    }
                }
            }
        }

        /// Parses `text` -- the raw bytes `git cat-file -p <object>`
        /// produced -- as an `action.yml`, or reports `.unreachable`
        /// when it doesn't parse as YAML. A parse failure is treated
        /// the same as an unreadable object: fail closed either way.
        static func parsed(_ text: String, object: String) -> Resolution {
            guard let root = try? CI.Workflow.YAML.Parser.parse(text) else {
                return .unreachable(reason: "\(object) did not parse as YAML")
            }
            return .resolved(
                Schema(
                    inputs: Self.keys(of: root["inputs"]),
                    outputs: Self.keys(of: root["outputs"])))
        }

        static func keys(of node: CI.Workflow.YAML.Node?) -> Set<String> {
            Set(node?.mapping?.textKeys ?? [])
        }

        /// `true` when `gitRoot` is a shallow checkout (`git rev-parse
        /// --is-shallow-repository` prints `true`), the signal that an
        /// unreachable object might just be un-fetched history rather
        /// than a genuinely absent commit. A `git` failure here (not a
        /// git repository at all, `git` missing) reads as "not
        /// shallow" -- there is nothing to fetch against in that case
        /// either, so the original fail-closed path still applies.
        static func isShallowRepository(gitRoot: String) -> Bool {
            guard
                case .success(let text) = Self.run([
                    "git", "-C", gitRoot, "rev-parse", "--is-shallow-repository",
                ])
            else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }

        /// The remotes configured in `gitRoot`, in `git remote`'s
        /// listed order.
        static func remotes(gitRoot: String) -> [String] {
            guard case .success(let text) = Self.run(["git", "-C", gitRoot, "remote"])
            else { return [] }
            return text.split(whereSeparator: \.isNewline).map(String.init)
        }

        /// One targeted `git fetch --depth 1 <remote> <sha>` against
        /// `gitRoot`'s `origin` remote if one exists, else its first
        /// configured remote. A checkout with no remote at all cannot
        /// be fetched into by definition -- that is reported as a
        /// failure here rather than attempted, and the caller folds it
        /// into the same fail-closed `.unreachable` outcome as a fetch
        /// that ran and still came up empty.
        private static func fetch(_ sha: String, gitRoot: String) -> ProcessOutcome {
            let configured = Self.remotes(gitRoot: gitRoot)
            guard let remote = configured.contains("origin") ? "origin" : configured.first
            else { return .failure("no git remote configured in \(gitRoot) to fetch from") }
            return Self.run(["git", "-C", gitRoot, "fetch", "--depth", "1", remote, sha])
        }

        /// A subprocess's outcome: its stdout text, or the failure
        /// reason a caller reports on an unreachable object.
        private enum ProcessOutcome {
            case success(String)
            case failure(String)
        }

        /// Serializes the spawn window -- pipe creation through
        /// `Process.run()` -- across every concurrent `run(_:)` call in
        /// this process. Between `Pipe()` and the post-spawn close of
        /// the parent's write-end copies, those descriptors are open in
        /// this parent and are inherited by ANY child forked in that
        /// window. A sibling git process that inherits them keeps the
        /// pipe's write end alive after our own child exits, so the
        /// drain below never sees EOF and `group.wait()` blocks
        /// forever. Swift Testing runs suites in parallel and every
        /// fixture shells out to git, so the race window is hit in
        /// practice, not just in theory. Only the spawn is serialized;
        /// draining and waiting stay concurrent.
        ///
        /// Internal (not private) deliberately: the guarantee only
        /// holds if EVERY spawner in the process serializes through the
        /// same queue, so the test target's fixture git spawns share it
        /// via `@testable` rather than minting a second queue that
        /// cannot exclude this one.
        static let spawning = DispatchQueue(
            label: "institute-ci.pinned-content.spawn")

        /// Runs a subprocess to completion, capturing stdout as text on
        /// success and stderr as the failure reason on a non-zero exit
        /// or a launch failure.
        ///
        /// Drains stdout and stderr CONCURRENTLY rather than reading
        /// one pipe to completion before touching the other.
        /// Sequential draining is deadlock-shaped: an OS pipe has a
        /// bounded buffer, so once git writes enough to the side
        /// nothing is reading yet -- `git fetch`'s progress chatter on
        /// stderr is easily enough -- the child blocks inside its own
        /// `write()` forever and this call never returns.
        ///
        /// The off-thread drain is a real `Thread`, NOT a dispatched
        /// work item. Under Swift Testing's parallel runner every
        /// concurrent caller of this function occupies (and blocks) a
        /// cooperative-pool thread, and those threads ARE libdispatch's
        /// worker pool on Darwin -- observed in the field as a whole
        /// suite parked in a dispatch-group wait with the drain work
        /// items queued but never executed, no worker left to run
        /// them. A detached thread runs regardless of pool state.
        /// stderr is drained on the calling thread (already committed
        /// to blocking until the child finishes), stdout on the
        /// detached thread; the semaphore wait happens-after the
        /// detached write to `outData`, so reading it afterward is
        /// safe.
        private static func run(_ arguments: [String]) -> ProcessOutcome {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            let stdout: Pipe
            let stderr: Pipe
            do {
                (stdout, stderr) = try Self.spawning.sync {
                    let out = Pipe()
                    let err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    try process.run()
                    return (out, err)
                }
            } catch {
                return .failure("could not launch: \(error)")
            }

            nonisolated(unsafe) var outData = Data()
            let drained = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                outData = stdout.fileHandleForReading.readDataToEndOfFile()
                drained.signal()
            }
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            drained.wait()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let errorText = String(decoding: errData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(errorText.isEmpty ? "exit \(process.terminationStatus)" : errorText)
            }
            return .success(String(decoding: outData, as: UTF8.self))
        }
    }
}
