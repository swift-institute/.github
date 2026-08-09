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
        public static func resolve(_ coordinate: Coordinate, gitRoot: String) -> Resolution {
            let object = "\(coordinate.sha):\(coordinate.path)/action.yml"
            switch Self.run(["git", "-C", gitRoot, "cat-file", "-p", object]) {
            case .failure(let reason):
                return .unreachable(reason: "git cat-file \(object) failed: \(reason)")
            case .success(let text):
                guard let root = try? CI.Workflow.YAML.Parser.parse(text) else {
                    return .unreachable(reason: "\(object) did not parse as YAML")
                }
                return .resolved(
                    Schema(
                        inputs: Self.keys(of: root["inputs"]),
                        outputs: Self.keys(of: root["outputs"])))
            }
        }

        static func keys(of node: CI.Workflow.YAML.Node?) -> Set<String> {
            Set(node?.mapping?.textKeys ?? [])
        }

        /// A subprocess's outcome: its stdout text, or the failure
        /// reason a caller reports on an unreachable object.
        private enum ProcessOutcome {
            case success(String)
            case failure(String)
        }

        /// Runs a subprocess to completion, capturing stdout as text on
        /// success and stderr as the failure reason on a non-zero exit
        /// or a launch failure.
        private static func run(_ arguments: [String]) -> ProcessOutcome {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return .failure("could not launch: \(error)")
            }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
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
