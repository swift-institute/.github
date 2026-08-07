import CI_Contract
import CI_Workflow
import Foundation
import Institute_Receipt
import Testing

/// Fail-closed controls for `swift-ci.yml`'s published-linter installer,
/// ported from `.github/scripts/tests/test-ci-binaries-identity.py`.
///
/// The suite tests the *shipped bytes*: it extracts the installation
/// step out of the workflow by name and runs it against a hermetic
/// release fixture. A rewritten Swift transcription of the step would
/// prove that the transcription is fail-closed and say nothing about
/// what CI actually executes.
///
/// The one thing that changed in the port is the extractor: the step is
/// read through `CI.Workflow.Document` rather than PyYAML, which is the
/// same reader every ported validator uses and one fewer YAML
/// implementation in the tree.
extension Institute.Receipt.Bootstrap {
    @Suite
    struct Installer {
        @Suite
        struct Integration {}

        static let jobIdentifier = "swift-linter"
        static let stepName = "Install published linter binaries"
        static let authorities = [
            "engine",
            "swift-primitives-linter-rules",
            "swift-standards-linter-rules",
            "swift-institute-linter-rules",
            "swift-linter-rules",
            "swift-linter-primitives",
        ]

        /// `swift-institute/.github` — four levels above this file
        /// (`Tools/institute-ci/Tests/<target>/`).
        static var repositoryRoot: URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        static var workflow: URL {
            repositoryRoot.appendingPathComponent(".github/workflows/swift-ci.yml")
        }

        /// The step's `run:` body, by job id and step name.
        ///
        /// A rename on either side must fail loudly here rather than quietly
        /// test nothing, so absence is a thrown refusal and not an empty
        /// script.
        static func installationStep() throws -> String {
            let text = try String(contentsOf: workflow, encoding: .utf8)
            let document = try CI.Workflow.Document(name: "swift-ci.yml", text: text)
            let job = try #require(
                document.jobs.first { $0.name == jobIdentifier },
                "\(workflow.path): no job '\(jobIdentifier)' — the extraction target is gone")
            let step = try #require(
                job.steps.first { $0["name"]?.text == stepName },
                "\(workflow.path): job '\(jobIdentifier)' has no step named '\(stepName)' — this suite tests the shipped bytes by name, so rename it here too")
            return try #require(step["run"]?.text, "step '\(stepName)' has no run: body")
        }

        struct Outcome {
            let status: Int32
            let output: String
            let installed: Bool
        }

        /// Runs the shipped step against a hermetic release fixture.
        ///
        /// Nothing leaves the temporary directory: `curl` serves the fixture,
        /// `install` records rather than writes, and `sha256sum` is provided
        /// where the platform spells it `shasum` — so the check under test is
        /// the step's own refusal logic and never the runner's toolbox.
        static func run(manifest: String, corrupt: Bool = false) throws -> Outcome {
            let root = URL(
                fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
            ).appendingPathComponent("ci-binaries-\(UUID().uuidString)")
            let release = root.appendingPathComponent("release")
            let shims = root.appendingPathComponent("bin")
            let manager = FileManager.default
            try manager.createDirectory(at: release, withIntermediateDirectories: true)
            try manager.createDirectory(at: shims, withIntermediateDirectories: true)
            // failure to clean up a temporary directory is not a test
            // result.
            // swift-linter:disable:next try optional
            // REASON: FileManager.removeItem(at:) throws untyped, and failing to clean a temporary directory is not a test result.
            defer { try? manager.removeItem(at: root) }

            try "#!binary-one\n".write(
                to: release.appendingPathComponent("swift-linter"), atomically: true, encoding: .utf8)
            try "#!binary-two\n".write(
                to: release.appendingPathComponent("swift-linter-runner"), atomically: true,
                encoding: .utf8)
            try manifest.write(
                to: release.appendingPathComponent("MANIFEST.txt"), atomically: true, encoding: .utf8)

            let installed = root.appendingPathComponent("installed.log")
            try write(
                """
                #!/usr/bin/env bash
                # The platform that spells it `shasum` gets the same interface.
                if command -v /usr/bin/sha256sum >/dev/null 2>&1; then
                  exec /usr/bin/sha256sum "$@"
                fi
                mapped=()
                for argument in "$@"; do
                  case "$argument" in
                    --check) mapped+=(-c) ;;
                    *) mapped+=("$argument") ;;
                  esac
                done
                exec shasum -a 256 "${mapped[@]}"
                """,
                to: shims.appendingPathComponent("sha256sum"))
            try write(
                """
                #!/usr/bin/env bash
                # Hermetic shim: serve the requested release fixture asset.
                destination=""
                url=""
                while [ $# -gt 0 ]; do
                  case "$1" in
                    -o|--output) destination="$2"; shift 2 ;;
                    *) url="$1"; shift ;;
                  esac
                done
                cp "\(release.path)/$(basename "$url")" "$destination"
                """,
                to: shims.appendingPathComponent("curl"))
            try write(
                """
                #!/usr/bin/env bash
                echo "$@" >> "\(installed.path)"
                """,
                to: shims.appendingPathComponent("install"))

            let environmentPath = "\(shims.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
            try shell(
                "sha256sum MANIFEST.txt swift-linter swift-linter-runner > SHA256SUMS",
                in: release, path: environmentPath)
            if corrupt {
                try "#!tampered\n".write(
                    to: release.appendingPathComponent("swift-linter"), atomically: true,
                    encoding: .utf8)
            }

            let script = root.appendingPathComponent("step.sh")
            try installationStep().write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = environmentPath
            environment["GITHUB_OUTPUT"] = root.appendingPathComponent("github_output").path
            environment["GITHUB_STEP_SUMMARY"] = root.appendingPathComponent("github_summary").path
            environment["GITHUB_ENV"] = root.appendingPathComponent("github_env").path
            environment["LINTER_RELEASE"] = "https://fixture.invalid/ci-binaries"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return .init(
                status: process.terminationStatus,
                output: String(decoding: output, as: UTF8.self),
                installed: manager.fileExists(atPath: installed.path))
        }

        static func write(_ contents: String, to url: URL) throws {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        static func shell(_ command: String, in directory: URL, path: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = path
            process.environment = environment
            try process.run()
            process.waitUntilExit()
        }

        static func manifest(omitting authority: String? = nil) -> String {
            authorities
                .filter { $0 != authority }
                .map { "\($0)=\(String(repeating: "a", count: 40))\n" }
                .joined()
        }

        @Suite
        struct Unit {
            @Test func `a complete manifest installs`() throws {
                let outcome = try Institute.Receipt.Bootstrap.Installer.run(
                    manifest: Institute.Receipt.Bootstrap.Installer.manifest())
                #expect(outcome.status == 0, "\(outcome.output)")
                #expect(outcome.installed)
            }
        }

        @Suite
        struct `Edge Case` {
            /// Completeness, not currency: a release whose manifest omits an
            /// authority is one whose rule provenance cannot be stated.
            @Test func `a manifest omitting an authority refuses to install`() throws {
                let outcome = try Institute.Receipt.Bootstrap.Installer.run(
                    manifest: Institute.Receipt.Bootstrap.Installer.manifest(omitting: "engine"))
                #expect(outcome.status != 0)
                #expect(outcome.output.contains("omits 'engine'"))
                #expect(!outcome.installed)
            }

            @Test func `a checksum mismatch refuses to install`() throws {
                let outcome = try Institute.Receipt.Bootstrap.Installer.run(
                    manifest: Institute.Receipt.Bootstrap.Installer.manifest(), corrupt: true)
                #expect(outcome.status != 0)
                #expect(!outcome.installed)
            }
        }
    }
}
