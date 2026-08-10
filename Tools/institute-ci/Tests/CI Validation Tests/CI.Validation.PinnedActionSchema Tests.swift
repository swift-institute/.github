import CI_Contract
import Foundation
import Testing

@testable import CI_Validation

/// `[CI-118]` controls.
///
/// Positive control reconstructs PR #500's original head (`d1d67da`):
/// an undeclared `with:` input plus a `steps.<id>.outputs.<name>`
/// reference the pinned revision never set. Negative control is a
/// legitimate call site. Edge proves a dynamic `with:` VALUE never
/// false-positives -- only the key is checked. Near-miss proves an
/// output name valid for a DIFFERENT step's action still fires when
/// referenced against the wrong step id. Real Tree is the mandatory
/// self-firing sweep over the committed workflow set.
@Suite
struct CIValidationPinnedActionSchemaTests {
    static let prefix = "swift-institute/.github/.github/actions/"

    static func actionYML(inputs: [String], outputs: [String]) -> String {
        var text = "name: fixture-action\ndescription: fixture\n"
        if !inputs.isEmpty {
            text += "inputs:\n"
            for input in inputs { text += "  \(input):\n    description: fixture\n" }
        }
        if !outputs.isEmpty {
            text += "outputs:\n"
            for output in outputs { text += "  \(output):\n    description: fixture\n" }
        }
        text += "runs:\n  using: composite\n  steps: []\n"
        return text
    }

    static func workflow(_ body: String) -> String {
        """
        name: fixture
        on: workflow_dispatch: {}
        jobs:
          example:
            runs-on: ubuntu-latest
            steps:
        \(body)
        """
    }

    /// Writes one fixture action into `repository` and commits it to a
    /// real git history (so `PinnedContent` resolves against an actual
    /// object, not the working tree), returning the commit SHA every
    /// fixture `uses:` line pins to.
    static func commitFixtureAction(
        in repository: borrowing TemporaryRepository,
        actionName: String = "install-example",
        inputs: [String], outputs: [String]
    ) -> String {
        repository.write(
            Self.actionYML(inputs: inputs, outputs: outputs),
            to: ".github/actions/\(actionName)/action.yml")
        return repository.gitCommit()
    }

    @Suite
    struct `Positive Control` {
        @Test func `an undeclared with key and an absent output both fire, reconstructing 500`() throws {
            // #500's original head: `skip-on-missing-release` was an
            // undeclared input, and `steps.install.outputs.installed`
            // referenced an output the pinned revision never set.
            let repository = TemporaryRepository()
            let sha = CIValidationPinnedActionSchemaTests.commitFixtureAction(
                in: repository, actionName: "install-swift-sdk",
                inputs: ["platform", "sdk-id"], outputs: [])
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - name: Install
                            id: install
                            uses: \(CIValidationPinnedActionSchemaTests.prefix)install-swift-sdk@\(sha)
                            with:
                              platform: wasm-sdk
                              sdk-id: ${TAG}_wasm
                              skip-on-missing-release: 'true'
                          - name: Build
                            id: build
                            if: steps.install.outputs.installed == 'true'
                            run: echo build
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.allSatisfy { $0.rule == "CI-118" })
            #expect(findings.contains { $0.message.contains("skip-on-missing-release") })
            #expect(findings.contains { $0.message.contains("steps.install.outputs.installed") })
            #expect(findings.count == 2)
        }

        @Test func `an unreachable pinned object fires, failing closed`() throws {
            // No git history at all: the pin cannot be resolved, and
            // that absence of an answer is itself the violation -- never
            // a silently skipped call site.
            let repository = TemporaryRepository()
            let sha = String(repeating: "a", count: 40)
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - uses: \(CIValidationPinnedActionSchemaTests.prefix)install-example@\(sha)
                            with:
                              platform: wasm-sdk
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.count == 1)
            #expect(findings[0].rule == "CI-118")
            #expect(findings[0].message.contains("unreachable"))
        }
    }

    @Suite
    struct `Committed vs Worktree` {
        @Test func `resolution reads the pinned commit's object, never the current working tree`() throws {
            // The #500/#501 bug class exactly: a caller trusts what the
            // pin NAMES, not what happens to be on disk right now. Every
            // other fixture in this suite has committed == worktree for
            // action.yml, so none of them could catch an implementation
            // that accidentally reads the working copy instead of the
            // git object at the pinned SHA. Here the two diverge: the
            // COMMITTED revision (what the pin names) does not declare
            // `extra-input`, but the file on disk right now (as if HEAD
            // moved on since the pin was taken) does. A correct
            // `git cat-file -p <sha>:<path>` read is blind to that
            // later edit and must still fire.
            let repository = TemporaryRepository()
            let sha = CIValidationPinnedActionSchemaTests.commitFixtureAction(
                in: repository, actionName: "install-example",
                inputs: ["platform"], outputs: [])
            // Overwrite the working copy AFTER the commit, without
            // committing again -- HEAD's tree (and the pinned SHA) both
            // still lack `extra-input`; only the file on disk has it.
            repository.write(
                CIValidationPinnedActionSchemaTests.actionYML(
                    inputs: ["platform", "extra-input"], outputs: []),
                to: ".github/actions/install-example/action.yml")
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - uses: \(CIValidationPinnedActionSchemaTests.prefix)install-example@\(sha)
                            with:
                              platform: wasm-sdk
                              extra-input: 'true'
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.count == 1)
            #expect(findings[0].message.contains("extra-input"))
        }
    }

    @Suite
    struct `Shallow Checkout` {
        @Test func `a pinned commit older than the shallow boundary is fetched and resolved, not falsely flagged`() throws {
            // CI's `tools-tests.yml` runs this very suite with
            // `fetch-depth: 1`. A pin to a commit older than the
            // shallow boundary is unreachable via LOCAL git object
            // access even though it is a perfectly valid pin -- the
            // fix is a targeted `git fetch --depth 1 <remote> <sha>`
            // before concluding `.unreachable`. This reproduces that
            // shape for real: a full-history origin repository, a
            // shallow clone of it whose only local commit is the tip,
            // and a workflow in the shallow clone pinning to the OLDER
            // (locally-absent-but-fetchable) commit.
            let origin = TemporaryRepository()
            let oldSHA = CIValidationPinnedActionSchemaTests.commitFixtureAction(
                in: origin, actionName: "install-example",
                inputs: ["platform"], outputs: [])
            // A second commit advances the tip so the shallow clone's
            // one fetched commit is NOT the one the workflow pins to.
            origin.write("advance\n", to: "NOTES.md")
            origin.gitCommit()

            let shallowRoot = NSTemporaryDirectory() + "institute-ci-tests/" + UUID().uuidString
            let clone = Process()
            clone.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            // A plain local-path clone IGNORES --depth (git hardlinks the
            // full object store); only a file:// URL clone is genuinely
            // shallow. The cat-file probe below is the positive control
            // that the pinned commit really is absent locally.
            clone.arguments = [
                "git", "clone", "-q", "--depth", "1",
                "file://" + origin.root, shallowRoot,
            ]
            // Serialized like every other spawn in this process; see
            // `TemporaryRepository.run`.
            try CI.Validation.PinnedContent.spawning.sync { try clone.run() }
            clone.waitUntilExit()
            #expect(clone.terminationStatus == 0)
            defer { try? FileManager.default.removeItem(atPath: shallowRoot) }

            // Confirm the fixture actually reproduces the trap: the
            // pinned commit must be genuinely absent from the shallow
            // clone's local objects before the fetch-and-retry runs.
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            probe.arguments = ["git", "-C", shallowRoot, "cat-file", "-e", oldSHA]
            probe.standardOutput = FileHandle.nullDevice
            probe.standardError = FileHandle.nullDevice
            try CI.Validation.PinnedContent.spawning.sync { try probe.run() }
            probe.waitUntilExit()
            #expect(probe.terminationStatus != 0)

            let path = ".github/actions/install-example"
            let coordinate = CI.Validation.PinnedContent.Coordinate(path: path, sha: oldSHA)
            let resolution = CI.Validation.PinnedContent.resolve(coordinate, gitRoot: shallowRoot)
            switch resolution {
            case .resolved(let schema):
                #expect(schema.inputs == ["platform"])
            case .unreachable(let reason):
                Issue.record("expected the shallow-clone fetch-and-retry to resolve; got: \(reason)")
            }
        }
    }

    @Suite
    struct `Negative Control` {
        @Test func `a legitimate call site is silent`() throws {
            let repository = TemporaryRepository()
            let sha = CIValidationPinnedActionSchemaTests.commitFixtureAction(
                in: repository, actionName: "install-swift-sdk",
                inputs: ["platform", "sdk-id", "skip-on-missing-release"],
                outputs: ["installed"])
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - name: Install
                            id: install
                            uses: \(CIValidationPinnedActionSchemaTests.prefix)install-swift-sdk@\(sha)
                            with:
                              platform: wasm-sdk
                              sdk-id: ${TAG}_wasm
                              skip-on-missing-release: 'true'
                          - name: Build
                            id: build
                            if: steps.install.outputs.installed == 'true'
                            run: echo build
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.isEmpty)
        }
    }

    @Suite
    struct Edge {
        @Test func `a dynamic with value on a declared key never false positives`() throws {
            // Only the KEY is checked. A templated VALUE resolved at
            // runtime is exactly what `with:` is for and must never
            // fire, no matter how dynamic the expression looks.
            let repository = TemporaryRepository()
            let sha = CIValidationPinnedActionSchemaTests.commitFixtureAction(
                in: repository, actionName: "install-example",
                inputs: ["platform"], outputs: [])
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - uses: \(CIValidationPinnedActionSchemaTests.prefix)install-example@\(sha)
                            with:
                              platform: ${{ matrix.platform || format('{0}-sdk', github.run_id) }}
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.isEmpty)
        }
    }

    @Suite
    struct `Near Miss` {
        @Test func `an output valid for a different step's action still fires against the wrong step id`() throws {
            let repository = TemporaryRepository()
            repository.write(
                CIValidationPinnedActionSchemaTests.actionYML(inputs: [], outputs: ["foo"]),
                to: ".github/actions/action-a/action.yml")
            repository.write(
                CIValidationPinnedActionSchemaTests.actionYML(inputs: [], outputs: ["bar"]),
                to: ".github/actions/action-b/action.yml")
            let sha = repository.gitCommit()
            let prefix = CIValidationPinnedActionSchemaTests.prefix
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - id: a
                            uses: \(prefix)action-a@\(sha)
                          - id: b
                            uses: \(prefix)action-b@\(sha)
                            if: steps.b.outputs.foo == 'true'
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.count == 1)
            #expect(findings[0].message.contains("steps.b.outputs.foo"))
        }

        @Test func `the same output referenced against the declaring step's own id is silent`() throws {
            // Control for the near-miss above: `foo` referenced against
            // `steps.a` (the step whose action DOES declare it) must not
            // fire -- proving the near-miss above fired on the step id,
            // not merely on the output name existing somewhere.
            let repository = TemporaryRepository()
            repository.write(
                CIValidationPinnedActionSchemaTests.actionYML(inputs: [], outputs: ["foo"]),
                to: ".github/actions/action-a/action.yml")
            repository.write(
                CIValidationPinnedActionSchemaTests.actionYML(inputs: [], outputs: ["bar"]),
                to: ".github/actions/action-b/action.yml")
            let sha = repository.gitCommit()
            let prefix = CIValidationPinnedActionSchemaTests.prefix
            repository.write(
                CIValidationPinnedActionSchemaTests.workflow(
                    """
                          - id: a
                            uses: \(prefix)action-a@\(sha)
                            if: steps.a.outputs.foo == 'true'
                          - id: b
                            uses: \(prefix)action-b@\(sha)
                    """
                ),
                to: ".github/workflows/fixture.yml"
            )
            let findings = try CI.Validation.PinnedActionSchema().findings(in: repository.subject)
            #expect(findings.isEmpty)
        }
    }

    @Suite
    struct `Real Tree` {
        @Test func `every committed call site corresponds to its pinned action's declared schema`() throws {
            // The mandatory self-firing sweep: this must report ZERO
            // findings at head. A future change that reverts the fix, or
            // introduces a new mismatched call site, turns this red.
            let findings = try CI.Validation.PinnedActionSchema()
                .findings(in: RepositoryUnderTest.subject)
            #expect(findings.filter { $0.rule == "CI-118" }.isEmpty)
        }
    }
}
