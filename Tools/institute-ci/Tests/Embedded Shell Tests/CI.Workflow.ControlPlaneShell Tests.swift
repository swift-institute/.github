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

        @Test func `a sh-compatible sibling does not stand in for the target shell contract`() throws {
            let shell = try EmbeddedShell.workflowStep(
                ControlPlaneShellTests.workflow,
                job: "embedded", step: "Print Swift version")
            #expect(shell.shell == nil)
            #expect(shell.script == "swift --version")
        }
    }

    /// The checked-out central config is the effective policy only when a
    /// consumer does not own a root configuration file.
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
                      if [ "$1" = lint ] && [ "$2" = . ]; then
                        expected="$GITHUB_WORKSPACE/.ci-central-swiftlint-config/.swiftlint.yml"
                        if [ ! -L .swiftlint.yml ] || [ "$(readlink .swiftlint.yml)" != "$expected" ]; then
                          echo 'rootless consumer did not link the checked-out central config' >&2
                          return 95
                        fi
                        count=$(find "$2" -type f -name '*.swift' | wc -l)
                        if [ "$count" -eq 0 ]; then
                          echo 'rootless consumer selected zero lintable source paths' >&2
                          return 96
                        fi
                        printf 'SWIFTLINT_ROOTLESS_CONFIG=linked\\n'
                        printf 'SWIFTLINT_ROOTLESS_LINTABLE_FILES=%s\\n' "$count"
                      fi
                      printf 'SWIFTLINT_CALL=%s\\n' "$*"
                    }
                    """,
                in: directory)
        }

        @Test func `a rootless consumer lints its own source path with the checked-out central config`() throws {
            let result = try Self.run(
                hasRootConfig: false, source: "struct Example {}\\n")
            #expect(result.status == 0, "\(result.log)")
            #expect(result.log.contains("SWIFTLINT_ROOTLESS_CONFIG=linked"))
            #expect(result.log.contains("SWIFTLINT_ROOTLESS_LINTABLE_FILES=1"))
            #expect(result.log.contains(
                "SWIFTLINT_CALL=lint . --strict --reporter github-actions-logging"))
        }

        @Test func `a consumer root config retains the existing resolution path`() throws {
            let result = try Self.run(hasRootConfig: true)
            #expect(result.status == 0, "\(result.log)")
            #expect(result.log.contains(
                "SWIFTLINT_CALL=lint --strict --reporter github-actions-logging"))
            #expect(!result.log.contains("--config"))
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
