import CI_Contract
import CI_Workflow
import Foundation
import Testing

/// Positive controls for `swift-ci.yml`'s embedded control-plane shell.
///
/// Shell embedded in a workflow is exactly the shape that went wrong:
/// `ci-ok` spent eight days reporting success over runs that compiled
/// nothing, because `all(.result == "success" or .result == "skipped")`
/// cannot tell a plan-sanctioned skip from a leg that stopped running.
/// Reasoning about whether an aggregator would fire is not the same act
/// as watching it fire (swift-institute/Internal `VALIDATOR-DISCIPLINE.md`
/// §3), so these feed it the shapes it must reject and assert the exit
/// status *and* the diagnostic.
@Suite
struct ControlPlaneShellTests {
    static let workflow = ".github/workflows/swift-ci.yml"
    static let resolveSubjectStep = "Resolve CI subject"

    /// The configured-rule path must not report a clean run over no
    /// measure.
    @Suite
    struct ConfiguredLinterAdjudication {
        static func run(
            output: String, exit: Int = 0
        ) throws -> EmbeddedShell.Result {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "swift-linter", step: "Run swift-linter (consumer Lint.swift)")
            let directory = URL(
                fileURLWithPath: NSTemporaryDirectory() + "linter-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            return try shell.run(
                environment: [
                    "LINTER_OUTPUT": output,
                    "LINTER_EXIT": String(exit),
                    "GITHUB_WORKSPACE": directory.path,
                ],
                preamble: """
                    swift-linter() {
                      if [ "$2" != "--exit-policy" ] || [ "$3" != "strict" ]; then
                        echo "unexpected swift-linter arguments: $*"
                        return 97
                      fi
                      printf '%s\\n' "$LINTER_OUTPUT"
                      return "$LINTER_EXIT"
                    }
                    """,
                in: directory)
        }

        @Test func `a real configured run passes and is summarised`() throws {
            let result = try Self.run(output: "93 active rules · 4 files linted · 0 violations")
            #expect(result.status == 0, "\(result.log)")
            #expect(result.summary.contains("swift-linter (Lint.swift)"))
        }

        @Test func `a run that emitted no summary fails`() throws {
            let result = try Self.run(output: "no summary was emitted")
            #expect(result.status != 0)
            #expect(result.log.contains("emitted no run summary"))
        }

        @Test func `zero active rules fails`() throws {
            let result = try Self.run(output: "0 active rules · 4 files linted · 0 violations")
            #expect(result.status != 0)
            #expect(result.log.contains("loaded 0 rules from Lint.swift"))
        }

        @Test func `zero linted files fails`() throws {
            let result = try Self.run(output: "93 active rules · 0 files linted · 0 violations")
            #expect(result.status != 0)
            #expect(result.log.contains("linted 0 files"))
        }

        @Test func `an existing strict failure is preserved`() throws {
            let result = try Self.run(
                output: "93 active rules · 4 files linted · 1 violation", exit: 42)
            #expect(result.status == 42, "\(result.log)")
        }
    }

    /// The single subject-resolution contract (swift-institute/.github#179).
    ///
    /// Before this step existed, the Plan job's own checkout resolved
    /// `repository:` independently of `ref:`, so a dispatch supplying
    /// `target-repo` without `ref` checked out the TARGET repository at
    /// the TRIGGERING repository's SHA — a commit that does not exist
    /// there. Regression: PR #179 merge 5685c9e3, run 30875153360, Plan
    /// failure 57/57, 912 skipped leaf jobs.
    @Suite
    struct ResolveSubject {
        /// `gh` shimmed by exact invocation. A `nil` reply is a 404 —
        /// empty stdout, nonzero exit — which is what the script's `||
        /// true` fallback has to turn into an empty, fail-closed value
        /// rather than a crash.
        static func run(
            gh replies: [String: String?] = [:], environment: [String: String] = [:]
        ) throws -> EmbeddedShell.Result {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "plan", step: ControlPlaneShellTests.resolveSubjectStep)
            var preamble = ["gh() {", #"  case "$*" in"#]
            for (call, reply) in replies.sorted(by: { $0.key < $1.key }) {
                let escaped = call.replacingOccurrences(of: "'", with: #"'\''"#)
                if let reply {
                    preamble.append(
                        "    '\(escaped)') printf '%s\\n' '"
                            + reply.replacingOccurrences(of: "'", with: #"'\''"#) + "' ;;")
                } else {
                    preamble.append("    '\(escaped)') return 1 ;;")
                }
            }
            preamble.append(#"    *) echo "unexpected gh invocation: $*" >&2; return 99 ;;"#)
            preamble.append("  esac")
            preamble.append("}")

            var base = [
                "EVENT_NAME": "push",
                "INPUT_TARGET_REPOSITORY": "",
                "INPUT_REF": "",
                "PULL_REQUEST_HEAD_REPOSITORY": "",
                "PULL_REQUEST_HEAD_SHA": "",
                "TRIGGER_REPOSITORY": "swift-institute/example",
                "TRIGGER_SHA": String(repeating: "a", count: 40),
            ]
            base.merge(environment) { _, new in new }
            return try shell.run(
                environment: base, preamble: preamble.joined(separator: "\n") + "\n")
        }

        @Test func `a target repo with an empty ref resolves the live default branch head`()
            throws
        {
            // Never the triggering repository's SHA — the #179 defect,
            // made to fail here.
            let result = try Self.run(
                gh: [
                    "api repos/mock/target --jq .default_branch": "main",
                    "api repos/mock/target/commits/main --jq .sha": String(repeating: "1", count: 40),
                ],
                environment: [
                    "INPUT_TARGET_REPOSITORY": "mock/target",
                    "INPUT_REF": "",
                    "TRIGGER_SHA": String(repeating: "9", count: 40),
                ])
            #expect(result.status == 0, "\(result.log)")
            #expect(result.outputs["subject-repository"] == "mock/target")
            #expect(result.outputs["subject-sha"] == String(repeating: "1", count: 40))
            #expect(result.outputs["subject-ref"] == String(repeating: "1", count: 40))
        }

        @Test func `an explicit ref resolves to one commit sha`() throws {
            let result = try Self.run(
                gh: [
                    "api repos/mock/target/commits/release-branch --jq .sha":
                        String(repeating: "2", count: 40)
                ],
                environment: [
                    "INPUT_TARGET_REPOSITORY": "mock/target",
                    "INPUT_REF": "release-branch",
                ])
            #expect(result.status == 0, "\(result.log)")
            #expect(result.outputs["subject-sha"] == String(repeating: "2", count: 40))
            #expect(result.outputs["subject-ref"] == String(repeating: "2", count: 40))
        }

        @Test func `an invalid explicit ref fails with no defaulting`() throws {
            let result = try Self.run(
                gh: ["api repos/mock/target/commits/does-not-exist --jq .sha": String?.none],
                environment: [
                    "INPUT_TARGET_REPOSITORY": "mock/target",
                    "INPUT_REF": "does-not-exist",
                ])
            #expect(result.status != 0)
            #expect(result.log.contains("could not resolve ref 'does-not-exist'"))
            #expect(result.outputs["subject-sha"] == nil)
        }

        @Test func `an inaccessible target repository fails closed`() throws {
            let result = try Self.run(
                gh: ["api repos/mock/missing --jq .default_branch": String?.none],
                environment: ["INPUT_TARGET_REPOSITORY": "mock/missing", "INPUT_REF": ""])
            #expect(result.status != 0)
            #expect(result.log.contains("could not read the default branch"))
            #expect(result.outputs["subject-sha"] == nil)
        }

        @Test func `a pull request uses the exact fork head with no api call`() throws {
            // A PR head SHA is already exact, so no resolution call is
            // needed or made: the shim has no registered replies, so any
            // `gh` call at all fails this.
            let result = try Self.run(environment: [
                "EVENT_NAME": "pull_request",
                "PULL_REQUEST_HEAD_REPOSITORY": "fork/example",
                "PULL_REQUEST_HEAD_SHA": String(repeating: "b", count: 40),
            ])
            #expect(result.status == 0, "\(result.log)")
            #expect(result.outputs["subject-repository"] == "fork/example")
            #expect(result.outputs["subject-sha"] == String(repeating: "b", count: 40))
            #expect(!result.log.contains("unexpected gh invocation"))
        }

        @Test func `an ordinary push uses the triggering repository and its exact sha`() throws {
            let result = try Self.run(environment: [
                "EVENT_NAME": "push",
                "TRIGGER_REPOSITORY": "swift-institute/example",
                "TRIGGER_SHA": String(repeating: "c", count: 40),
            ])
            #expect(result.status == 0, "\(result.log)")
            #expect(result.outputs["subject-repository"] == "swift-institute/example")
            #expect(result.outputs["subject-sha"] == String(repeating: "c", count: 40))
            #expect(!result.log.contains("unexpected gh invocation"))
        }

        @Test func `an empty subject fails closed`() throws {
            let result = try Self.run(environment: [
                "EVENT_NAME": "push", "TRIGGER_REPOSITORY": "", "TRIGGER_SHA": "",
            ])
            #expect(result.status != 0)
            #expect(result.log.contains("CI subject repository/SHA is empty"))
        }

        @Test func `a resolution result that is not a commit sha fails closed`() throws {
            let result = try Self.run(
                gh: ["api repos/mock/target/commits/main --jq .sha": "not-a-sha"],
                environment: [
                    "INPUT_TARGET_REPOSITORY": "mock/target", "INPUT_REF": "main",
                ])
            #expect(result.status != 0)
            #expect(result.log.contains("is not a 40-character commit SHA"))
        }
    }

    /// Fast tier compiles release; full qualification keeps release tests.
    @Suite
    struct ReleaseMode {
        static func run(job: String, tier: String, filter: String = "") throws
            -> EmbeddedShell.Result
        {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow, job: job, step: "Build or test (release)")
            let directory = URL(
                fileURLWithPath: NSTemporaryDirectory() + "release-" + UUID().uuidString)
            let binaries = directory.appendingPathComponent("bin")
            try FileManager.default.createDirectory(
                at: binaries, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let swift = binaries.appendingPathComponent("swift")
            try "#!/bin/sh\nprintf 'SWIFT_CALL=%s\\n' \"$*\"\n"
                .write(to: swift, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: swift.path)
            return try shell.run(
                environment: ["CI_TIER": tier, "TEST_FILTER": filter],
                path: binaries.path, in: directory)
        }

        @Test(arguments: ["linux-release", "linux-6-4"])
        func `the fast tier builds release without tests`(job: String) throws {
            let result = try Self.run(job: job, tier: "build")
            #expect(result.status == 0, "\(result.log)")
            #expect(result.log.contains("SWIFT_CALL=build -c release"))
            #expect(!result.log.contains("SWIFT_CALL=test"))
        }

        @Test func `the full tier keeps filtered release tests`() throws {
            let result = try Self.run(
                job: "linux-release", tier: "full", filter: "Report-Format")
            #expect(result.status == 0, "\(result.log)")
            #expect(result.log.contains("SWIFT_CALL=test -c release --filter Report_Format"))
        }
    }

    /// A selected Embedded target disables default traits only when the
    /// evaluated package manifest actually declares the reserved trait.
    @Suite
    struct EmbeddedTargetTraits {
        static func run(traits: String) throws -> EmbeddedShell.Result {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "embedded", step: "Build target (Embedded)")
            return try shell.run(
                environment: [
                    "EMBEDDED_TARGET": "Example",
                    "MANIFEST_JSON": #"{"traits":\#(traits)}"#,
                ],
                preamble: """
                    swift() {
                      case "$*" in
                        'package dump-package') printf '%s\n' "$MANIFEST_JSON" ;;
                        build*) printf 'SWIFT_CALL=%s\n' "$*" ;;
                        *) echo "unexpected swift invocation: $*" >&2; return 97 ;;
                      esac
                    }
                    """)
        }

        @Test func `a package with no traits omits the inapplicable flag`() throws {
            let result = try Self.run(traits: "[]")
            #expect(result.status == 0, "\(result.log)")
            #expect(
                result.log.contains(
                    "SWIFT_CALL=build --target Example -Xswiftc "
                        + "-enable-experimental-feature -Xswiftc Embedded"))
            #expect(!result.log.contains("--disable-default-traits"))
        }

        @Test func `a package with a default trait keeps the Embedded gate`() throws {
            let result = try Self.run(
                traits: #"[{"name":"Concurrency"},{"name":"default","enabledTraits":["Concurrency"]}]"#)
            #expect(result.status == 0, "\(result.log)")
            #expect(
                result.log.contains(
                    "SWIFT_CALL=build --target Example --disable-default-traits "
                        + "-Xswiftc -enable-experimental-feature -Xswiftc Embedded"))
        }

        @Test func `the selected target executes its pipefail script in Bash`() throws {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "embedded", step: "Build target (Embedded)")
            #expect(shell.shell == "bash")
            #expect(shell.script.contains("swift build --target \"$EMBEDDED_TARGET\""))
        }

        @Test func `a jq-free nightly fixture provisions manifest classification before building`() throws {
            let provisioner = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "embedded", step: "Install jq for manifest classification")
            let target = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "embedded", step: "Build target (Embedded)")
            let directory = URL(
                fileURLWithPath: NSTemporaryDirectory() + "embedded-jq-" + UUID().uuidString)
            let manager = FileManager.default
            try manager.createDirectory(
                at: directory.appendingPathComponent("Sources/Example"),
                withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: directory) }

            try """
                // swift-tools-version: 6.0
                import PackageDescription

                let package = Package(
                    name: "Example",
                    targets: [.target(name: "Example")])
                """.write(
                    to: directory.appendingPathComponent("Package.swift"),
                    atomically: true, encoding: .utf8)
            try "#error(\"selected Embedded build ran before manifest classification\")\n".write(
                to: directory.appendingPathComponent("Sources/Example/Example.swift"),
                atomically: true, encoding: .utf8)
            try provisioner.script.write(
                to: directory.appendingPathComponent("install-jq.sh"),
                atomically: true, encoding: .utf8)
            try target.script.write(
                to: directory.appendingPathComponent("build-target.sh"),
                atomically: true, encoding: .utf8)

            let missingProvisioning = try Self.nightly(
                in: directory, command: "bash build-target.sh")
            #expect(missingProvisioning.status != 0, "\(missingProvisioning.log)")
            #expect(missingProvisioning.log.contains("jq: command not found"))
            #expect(!missingProvisioning.log.contains(
                "selected Embedded build ran before manifest classification"))

            try "public struct Example {}\n".write(
                to: directory.appendingPathComponent("Sources/Example/Example.swift"),
                atomically: true, encoding: .utf8)

            let built = try Self.nightly(
                in: directory,
                command: """
                    command -v jq && exit 91
                    bash install-jq.sh
                    jq --version
                    bash build-target.sh
                    """)
            #expect(built.status == 0, "\(built.log)")
            #expect(built.log.contains("jq-"))
            #expect(built.log.contains("Build complete!"))
        }

        /// Runs the extracted shipped bytes in the same jq-free image as the
        /// `embedded` job. No command in this harness stands in for apt, jq,
        /// manifest evaluation, or the selected build.
        static func nightly(in directory: URL, command: String) throws -> EmbeddedShell.Result {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "docker", "run", "--rm",
                "--mount", "type=bind,source=\(directory.path),target=/fixture",
                "--workdir", "/fixture",
                "--env", "EMBEDDED_TARGET=Example",
                "swiftlang/swift:nightly-main-jammy",
                "bash", "-lc", command,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return .init(
                status: process.terminationStatus,
                log: String(decoding: output, as: UTF8.self),
                outputs: [:], summary: "")
        }

        @Test func `a sh-compatible sibling does not stand in for the target shell contract`() throws {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "embedded", step: "Print Swift version")
            #expect(shell.shell == nil)
            #expect(shell.script == "swift --version")
        }
    }

    /// A rootless consumer materializes the checked-out central config before
    /// selecting its own source paths. Its positive control runs the shipped
    /// bytes against the pinned Linux SwiftLint release, not a command shim.
    @Suite
    struct SwiftLintConfigSelection {
        static func run(hasRootConfig: Bool, source: String? = nil) throws -> EmbeddedShell.Result {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow, job: "lint", step: "Lint")
            let directory = URL(
                fileURLWithPath: NSTemporaryDirectory() + "swiftlint-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            if hasRootConfig {
                try "disabled_rules: []\n".write(
                    to: directory.appendingPathComponent(".swiftlint.yml"),
                    atomically: true, encoding: .utf8)
            }
            if let source {
                let sources = directory.appendingPathComponent("Sources")
                try FileManager.default.createDirectory(
                    at: sources, withIntermediateDirectories: true)
                try source.write(
                    to: sources.appendingPathComponent("Example.swift"),
                    atomically: true, encoding: .utf8)
            }
            if !hasRootConfig {
                let centralConfig = directory.appendingPathComponent(
                    ".ci-central-swiftlint-config/.swiftlint.yml")
                try FileManager.default.createDirectory(
                    at: centralConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "included: [Sources, Tests]\\n".write(
                    to: centralConfig, atomically: true, encoding: .utf8)
            }
            return try shell.run(
                environment: ["GITHUB_WORKSPACE": directory.path],
                preamble: """
                    swiftlint() {
                      printf 'SWIFTLINT_CALL=%s\\n' "$*"
                    }
                    """,
                in: directory)
        }

        @Test func `a rootless consumer selects and lints its own source path`() throws {
            let directory = URL(
                fileURLWithPath: NSTemporaryDirectory() + "swiftlint-real-" + UUID().uuidString)
            let manager = FileManager.default
            try manager.createDirectory(
                at: directory.appendingPathComponent("Sources"), withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: directory) }

            // `force_unwrapping` is a shipped default rule: the nonzero exit
            // and the rendered consumer path prove that SwiftLint selected
            // and linted this real file, rather than merely accepting the
            // command line.
            try "let value: Int? = nil\n_ = value!\n".write(
                to: directory.appendingPathComponent("Sources/Example.swift"),
                atomically: true, encoding: .utf8)
            let checkedOut = directory.appendingPathComponent(
                ".ci-central-swiftlint-config/.swiftlint.yml")
            try manager.createDirectory(
                at: checkedOut.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(
                at: URL(fileURLWithPath: EmbeddedShell.repositoryRoot + "/.swiftlint.yml"), to: checkedOut)

            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow, job: "lint", step: "Lint")
            let result = try Self.pinnedSwiftLint(shell, in: directory)
            #expect(result.status != 0, "\(result.log)")
            #expect(result.log.contains("Sources/Example.swift"))
            #expect(
                try String(contentsOf: directory.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
                    == String(contentsOf: checkedOut, encoding: .utf8))
        }

        @Test func `a rootless consumer with no source paths fails before SwiftLint`() throws {
            let result = try Self.run(hasRootConfig: false)
            #expect(result.status != 0)
            #expect(result.log.contains("rootless consumer has no Swift files"))
            #expect(!result.log.contains("SWIFTLINT_CALL="))
        }

        @Test func `a consumer root config retains the existing resolution path`() throws {
            let result = try Self.run(hasRootConfig: true)
            #expect(result.status == 0, "\(result.log)")
            #expect(result.log.contains(
                "SWIFTLINT_CALL=lint --strict --reporter github-actions-logging"))
            #expect(!result.log.contains("--config"))
        }

        /// The release URL and digest are the workflow's pinned Linux
        /// SwiftLint input. The real binary runs inside Ubuntu rather than
        /// borrowing a host-installed version.
        static func pinnedSwiftLint(_ shell: EmbeddedShell, in directory: URL)
            throws -> EmbeddedShell.Result
        {
            let script = directory.appendingPathComponent("lint.sh")
            try shell.script.write(to: script, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "docker", "run", "--rm", "--platform", "linux/amd64",
                "--mount", "type=bind,source=\(directory.path),target=/fixture",
                "--workdir", "/fixture",
                "--env", "GITHUB_WORKSPACE=/fixture",
                "ubuntu:24.04",
                "bash", "-lc",
                """
                set -euo pipefail
                apt-get update -qq
                apt-get install -qq -y ca-certificates curl libxml2 unzip
                curl -fsSL -o /tmp/swiftlint.zip \\
                  https://github.com/realm/SwiftLint/releases/download/0.63.3/swiftlint_linux_amd64.zip
                echo '26db741d43f2f2dc26c0cf16911100a3e186c3d1dbb59e55ad3ac87b0de4538f  /tmp/swiftlint.zip' | sha256sum -c -
                unzip -q /tmp/swiftlint.zip -d /tmp/swiftlint
                install -m 755 /tmp/swiftlint/swiftlint /usr/local/bin/swiftlint
                set +e
                bash lint.sh
                status=$?
                set -e
                test -f .swiftlint.yml
                test ! -L .swiftlint.yml
                cmp -s .swiftlint.yml .ci-central-swiftlint-config/.swiftlint.yml
                exit "$status"
                """,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return .init(
                status: process.terminationStatus,
                log: String(decoding: output, as: UTF8.self),
                outputs: [:], summary: "")
        }
    }

    /// R7 (swift-institute/.github#276): exactly one component derives
    /// the CI subject and every other consumer reads it.
    ///
    /// A fixture that re-asserts a fixed count protects against the two
    /// known offenders and nothing else, so this searches every step of
    /// every job for the *shape* of an independent recomputation — a
    /// subject-named variable assigned from a command substitution
    /// outside the one designated resolver step.
    @Suite
    struct SubjectDerivationSingularity {
        /// A line binding a `…SUBJECT…` variable to a command
        /// substitution — the shape of *deriving* a subject. Reading one
        /// supplied through `env:` never takes this shape; it is a bare
        /// `$VAR` reference, never the left of a `NAME=$(…)`.
        static func derivesSubject(_ line: Substring) -> Bool {
            guard let assignment = line.firstIndex(of: "=") else { return false }
            let name = line[line.startIndex..<assignment]
                .drop(while: { $0 == " " || $0 == "\t" })
            guard !name.isEmpty,
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  name.uppercased().contains("SUBJECT")
            else { return false }
            var rest = line[line.index(after: assignment)...]
            if rest.first == "\"" { rest = rest.dropFirst() }
            return rest.hasPrefix("$(")
        }

        static func offendingSites(
            in jobs: [(job: String, steps: [(name: String, run: String)])],
            exempting exempt: String = ControlPlaneShellTests.resolveSubjectStep
        ) -> [String] {
            var sites: [String] = []
            for job in jobs {
                for step in job.steps where step.name != exempt {
                    if step.run.split(separator: "\n").contains(where: derivesSubject) {
                        sites.append("\(job.job)/\(step.name)")
                    }
                }
            }
            return sites
        }

        static func shipped() throws -> [(job: String, steps: [(name: String, run: String)])] {
            let document = try EmbeddedShell.document(at: ControlPlaneShellTests.workflow)
            return document.jobs.map { job in
                (job.name, job.steps.compactMap { step in
                    guard let run = step["run"]?.text else { return nil }
                    return (step["name"]?.text ?? "", run)
                })
            }
        }

        @Test func `the shipped workflow has no independent recomputation`() throws {
            let sites = Self.offendingSites(in: try Self.shipped())
            #expect(
                sites.isEmpty,
                """
                found a step outside '\(ControlPlaneShellTests.resolveSubjectStep)' that \
                assigns a SUBJECT-named variable from a command substitution: \(sites). \
                This is the #179/ci-ok defect class — a second component deriving its own \
                opinion of the CI subject instead of reading Plan's single resolved output.
                """)
        }

        @Test func `the detector catches a reintroduced recomputation`() {
            // The standing fixture rule: a fixture whose passing state is
            // indistinguishable from the hazard being unreachable proves
            // nothing. This is what the control above failing looks like.
            let sites = Self.offendingSites(in: [
                ("plan", [(ControlPlaneShellTests.resolveSubjectStep, "echo ok\n")]),
                ("ci-ok", [
                    ("Aggregate required-job results",
                     "EXPECTED_SUBJECT_SHA=\"$(gh api repos/x/commits/main --jq .sha)\"\n")
                ]),
            ])
            #expect(sites == ["ci-ok/Aggregate required-job results"])
        }

        @Test func `the detector does not flag a pure consumer`() {
            let sites = Self.offendingSites(in: [
                ("plan", [
                    (ControlPlaneShellTests.resolveSubjectStep, "echo ok\n"),
                    ("Verify checked-out subject HEAD",
                     "ACTUAL=\"$(git rev-parse HEAD)\"\n"
                        + "if [ \"$ACTUAL\" != \"$SUBJECT_SHA\" ]; then exit 1; fi\n"),
                ])
            ])
            #expect(sites.isEmpty)
        }
    }
}
