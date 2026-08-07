import CI_Contract
import CI_Workflow
import Testing

@testable import CI_Validation

@Suite
struct CIValidationVisibilityGateTests {
    static func document(_ text: String) throws -> CI.Workflow.Document {
        try CI.Workflow.Document(name: "reusable.yml", text: text)
    }

    static let reusable = """
        name: r
        on:
          workflow_call:
        jobs:
        """

    @Suite
    struct Unit {
        @Test func `the validator is registered for its rule`() {
            let validator = CI.Validation.Registry.validator(for: "CI-032")
            #expect(validator is CI.Validation.VisibilityGate)
            #expect(
                validator?.retiredScript == ".github/scripts/validate-visibility-gate.py")
        }

        @Test func `a reusable is recognised in all three on spellings`() throws {
            // `on:` resolves to the boolean `true` under YAML 1.1, which
            // is why the map form is the one most likely to regress.
            for spelling in ["workflow_call:\n    inputs: {}", "workflow_call:"] {
                let document = try CIValidationVisibilityGateTests.document(
                    "on:\n  \(spelling)\njobs: {}\n")
                #expect(CI.Validation.VisibilityGate.isReusable(document))
            }
            #expect(
                CI.Validation.VisibilityGate.isReusable(
                    try CIValidationVisibilityGateTests.document("on: workflow_call\njobs: {}\n")))
            #expect(
                CI.Validation.VisibilityGate.isReusable(
                    try CIValidationVisibilityGateTests.document(
                        "on: [workflow_call]\njobs: {}\n")))
        }

        @Test func `a schedule only workflow is out of scope`() throws {
            // No consumer-callable surface, so no private-repository
            // concern — not a repository that passes, a question that is
            // not asked.
            let document = try CIValidationVisibilityGateTests.document(
                "on:\n  schedule:\n    - cron: '0 0 * * *'\njobs: {}\n")
            #expect(!CI.Validation.VisibilityGate.isReusable(document))
        }

        @Test func `a pure routing job is exempt`() throws {
            let document = try CIValidationVisibilityGateTests.document(
                CIValidationVisibilityGateTests.reusable + "\n  route:\n    uses: ./a.yml\n")
            #expect(CI.Validation.VisibilityGate.isPureRouting(document.jobs[0]))
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `a routing job that also carries work is not exempt`() throws {
            // The narrow half of the carve-out, and the one the corpus
            // pins with `fail/routing-plus-ungated-work`: real work never
            // reads as a shim.
            let document = try CIValidationVisibilityGateTests.document(
                CIValidationVisibilityGateTests.reusable
                    + "\n  half:\n    uses: ./a.yml\n    runs-on: ubuntu-latest\n")
            #expect(!CI.Validation.VisibilityGate.isPureRouting(document.jobs[0]))
        }

        @Test func `a disabled job is skipped in both spellings`() {
            #expect(CI.Validation.VisibilityGate.isDisabled(.boolean(false)))
            #expect(CI.Validation.VisibilityGate.isDisabled(.text(" False ")))
            #expect(!CI.Validation.VisibilityGate.isDisabled(.boolean(true)))
            #expect(!CI.Validation.VisibilityGate.isDisabled(nil))
        }

        @Test func `a boolean if stringifies the way Python printed it`() {
            // `if: true` reported as `'True'`, not `'true'`. The spelling
            // reaches the finding message, and the differential gate
            // compares it byte-for-byte.
            #expect(CI.Validation.VisibilityGate.text(of: .boolean(true)) == "True")
            #expect(CI.Validation.VisibilityGate.text(of: nil) == "")
            #expect(CI.Validation.VisibilityGate.text(of: .null) == "")
        }

        @Test func `an absent if is reported as the empty repr`() {
            let message = CI.Validation.VisibilityGate.message(
                document: "ci.yml", job: "build", clause: "")
            #expect(message.hasSuffix("got if=''"))
            #expect(message.contains("job 'build'"))
            #expect(message.contains(CI.Validation.VisibilityGate.gate))
        }

        @Test func `a clause containing an apostrophe switches quote`() {
            // Python's `repr` switches to double quotes rather than
            // escaping, and the message is compared byte-for-byte.
            let message = CI.Validation.VisibilityGate.message(
                document: "ci.yml", job: "b", clause: "github.event_name == 'push'")
            #expect(message.hasSuffix("got if=\"github.event_name == 'push'\""))
        }
    }
}
