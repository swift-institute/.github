import CI_Contract
import CI_Workflow
import Foundation
import Testing

@testable import CI_Validation

/// The four workflow-shape rules of class C1a — `[CI-040]`/`[CI-042]`,
/// `[CI-058]`, `[CI-080]`, `[CI-090]`/`[CI-097]`.
///
/// The fixture corpus is the primary evidence and the harness suite runs
/// it. These cover the seams a corpus of whole repositories reaches only
/// by accident: the Python `repr` a finding quotes, the three-state
/// reading of `permissions:`, first-step selection over a malformed
/// sequence. Those are where a byte-identity gate fails on a subject the
/// corpus happens not to contain.
@Suite
struct CIValidationWorkflowShapeTests {
    static var corpus: CI.Validation.Corpus {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }  // → repository root
        return .init(root: url.appendingPathComponent(".github/scripts/tests/fixtures").path)
    }

    /// The rules this class ports, and the script each replaces.
    static let ported: [CI.Validation.Rule: String] = [
        "CI-040": ".github/scripts/validate-cache-policy.py",
        "CI-042": ".github/scripts/validate-cache-policy.py",
        "CI-058": ".github/scripts/validate-input-defaults.py",
        "CI-080": ".github/scripts/validate-harden-runner.py",
        "CI-090": ".github/scripts/validate-permissions-shape.py",
        "CI-097": ".github/scripts/validate-permissions-shape.py",
    ]

    @Suite
    struct Unit {
        @Test func `a string renders in single quotes`() {
            #expect(CI.Workflow.YAML.Node.repr("scan") == "'scan'")
        }

        @Test func `scalars render as Python names, not Swift ones`() {
            // The finding quotes what PyYAML loaded, so `True`, not
            // `true`; `None`, not `nil`.
            #expect(CI.Workflow.YAML.Node.boolean(true).pythonRepr == "True")
            #expect(CI.Workflow.YAML.Node.null.pythonRepr == "None")
            #expect(CI.Workflow.YAML.Node.integer(3).pythonRepr == "3")
        }

        @Test func `str of a string is the string, repr of it is quoted`() {
            #expect(CI.Workflow.YAML.Node.text("v2").pythonString == "v2")
            #expect(CI.Workflow.YAML.Node.text("v2").pythonRepr == "'v2'")
        }

        @Test func `dot build is matched as a whole path component`() {
            #expect(CI.Validation.CachePolicy.namesBuildDirectory(".build"))
            #expect(CI.Validation.CachePolicy.namesBuildDirectory("./.build/"))
            #expect(CI.Validation.CachePolicy.namesBuildDirectory("a/.build"))
            #expect(!CI.Validation.CachePolicy.namesBuildDirectory("mybuild"))
            #expect(!CI.Validation.CachePolicy.namesBuildDirectory(".build-extra"))
        }

        @Test func `a digest pin is forty lower-case hex digits`() {
            let action = CI.Validation.HardenRunner.action
            #expect(
                CI.Validation.HardenRunner.isPinnedToDigest(
                    action + String(repeating: "a", count: 40)))
            #expect(!CI.Validation.HardenRunner.isPinnedToDigest(action + "v2.19.1"))
            #expect(
                !CI.Validation.HardenRunner.isPinnedToDigest(
                    action + String(repeating: "A", count: 40)))
        }

        @Test func `a routing job declares uses and no steps`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml",
                text: """
                    jobs:
                      route:
                        uses: ./.github/workflows/base.yml
                      work:
                        steps:
                          - run: true
                    """)
            #expect(CI.Validation.HardenRunner.isRouting(document.jobs[0]))
            #expect(!CI.Validation.HardenRunner.isRouting(document.jobs[1]))
        }

        @Test func `every ported rule resolves to the validator that replaces its script`() {
            for (rule, script) in CIValidationWorkflowShapeTests.ported {
                let validator = CI.Validation.Registry.validator(for: rule)
                #expect(validator != nil, "no validator registered for \(rule)")
                #expect(validator?.retiredScript == script)
            }
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `a string holding an apostrophe switches to double quotes`() {
            // Python's own quote rule. Workflow values are quoted YAML, so
            // both shapes reach a finding.
            #expect(CI.Workflow.YAML.Node.repr("it's") == "\"it's\"")
            #expect(CI.Workflow.YAML.Node.repr("it's \"x\"") == #"'it\'s "x"'"#)
        }

        @Test func `control characters escape rather than travel into the TSV`() {
            #expect(CI.Workflow.YAML.Node.repr("a\nb\tc") == #"'a\nb\tc'"#)
            #expect(CI.Workflow.YAML.Node.repr("\u{01}") == #"'\x01'"#)
        }

        @Test func `the restore-keys preview truncates by code point`() {
            // Python slices by code point, not by grapheme cluster, and
            // the two differ on a composed character at the boundary.
            #expect(CI.Validation.CachePolicy.preview(of: "  swift-\n  ") == "swift-")
            let composed = CI.Validation.CachePolicy.preview(
                of: "e\u{0301}" + String(repeating: "x", count: 100))
            #expect(composed.unicodeScalars.count == 80)
            #expect(composed.count == 79, "a grapheme-counting slice would keep 80 characters")
        }

        @Test func `a multi-line cache path is read line by line`() {
            #expect(CI.Validation.CachePolicy.namesBuildDirectory("~/.swiftpm\n.build\n"))
        }

        @Test func `both cache rules can fire on one step`() throws {
            let document = try CI.Workflow.Document(
                name: "ci.yml",
                text: """
                    jobs:
                      build:
                        steps:
                          - uses: actions/cache@v4
                            with:
                              path: .build
                              restore-keys: |
                                swift-
                    """)
            let job = try #require(document.jobs.first)
            let with = try #require(job.steps.first?["with"]?.mapping)
            let findings = CI.Validation.CachePolicy.findings(
                in: with, repository: "r", document: "ci.yml", job: "build")
            #expect(findings.map(\.rule) == ["CI-040", "CI-042"])
            #expect(findings[0].message.hasSuffix("path='.build'"))
            #expect(findings[1].message.hasSuffix("restore-keys preview: 'swift-'"))
        }

        @Test func `a malformed leading step is not skipped past`() throws {
            // The rule is about the FIRST step. A leading entry that is
            // not a mapping makes the first step uninspectable; reading
            // the second one instead would report on the wrong step.
            let document = try CI.Workflow.Document(
                name: "ci.yml",
                text: """
                    jobs:
                      build:
                        steps:
                          - just-a-string
                          - uses: actions/checkout@v4
                    """)
            #expect(CI.Validation.HardenRunner.firstStep(document.jobs[0]) == nil)
        }

        @Test func `absent, empty, and null permissions are three distinct states`() throws {
            let empty = try CI.Workflow.Document(
                name: "ci.yml", text: "on:\n  workflow_call:\npermissions: {}\n")
            let null = try CI.Workflow.Document(
                name: "ci.yml", text: "on:\n  workflow_call:\npermissions:\n")
            let absent = try CI.Workflow.Document(
                name: "ci.yml", text: "on:\n  workflow_call:\n")
            #expect(empty.body?["permissions"] == .mapping(.init([])))
            #expect(null.body?["permissions"] == .null)
            #expect(absent.body?["permissions"] == nil)
        }

        @Test func `only the boolean true satisfies the input-default rule`() throws {
            // The retired validator compared against Python's `True`
            // singleton, so the quoted string was already a violation.
            let base =
                "on:\n  workflow_call:\n    inputs:\n      enable-private-repos:\n        default:"
            func declared(_ text: String) throws -> CI.Workflow.YAML.Node? {
                try CI.Workflow.Document(name: "ci.yml", text: text)
                    .triggers?["workflow_call"]?["inputs"]?[CI.Validation.InputDefaults.input]?
                    .mapping?["default"]
            }
            #expect(try declared("\(base) true\n") == .boolean(true))
            #expect(try declared("\(base) 'true'\n") == .text("true"))
            #expect(try declared("\(base) false\n") == .boolean(false))
        }
    }

    @Suite
    struct Integration {
        @Test func `every ported rule has a fixture corpus that fires`() throws {
            // A validator registered against an empty corpus is a gate
            // that proves nothing; four in this repository sat inert.
            let harness = CI.Validation.Harness(corpus: CIValidationWorkflowShapeTests.corpus)
            let report = try harness.run()
            for rule in CIValidationWorkflowShapeTests.ported.keys.sorted() {
                let outcomes = report.outcomes.filter { $0.rule == rule }
                #expect(!outcomes.isEmpty, "\(rule) has no fixture scenarios")
                #expect(
                    outcomes.contains { $0.scenario.expectation == .violating },
                    "\(rule) has no fail/ scenario")
                for outcome in outcomes where !outcome.isSatisfied {
                    Issue.record("\(outcome.summary)")
                }
            }
        }

        @Test func `no ported rule directory remains unowned`() throws {
            let harness = CI.Validation.Harness(corpus: CIValidationWorkflowShapeTests.corpus)
            let report = try harness.run()
            let unowned = Set(report.unownedRuleDirectories)
            for rule in CIValidationWorkflowShapeTests.ported.keys {
                #expect(!unowned.contains(rule.rawValue.lowercased()))
            }
        }
    }
}
