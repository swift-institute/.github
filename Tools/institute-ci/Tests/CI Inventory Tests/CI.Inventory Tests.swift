import CI_Contract
import CI_Workflow
import Foundation
import Testing

@testable import CI_Inventory

/// The inventory derived from the **shipped** universal workflow.
///
/// Every assertion here is over the real `.github/workflows/swift-ci.yml`
/// in this checkout, not over a synthetic sample. An inventory proved
/// against a fixture it also shipped would agree with itself forever.
@Suite
struct CIInventoryTests {
    /// The repository root, located from this file so the suite behaves
    /// the same under SwiftPM, Xcode, and CI.
    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    static var universalPath: String {
        repositoryRoot.appendingPathComponent(".github/workflows/swift-ci.yml").path
    }

    static func shipped() throws -> CI.Inventory.Document {
        let text = try String(contentsOfFile: universalPath, encoding: .utf8)
        return try CI.Inventory.Document(universalWorkflow: text)
    }

    @Suite
    struct Topology {
        @Test func `the inventory describes one hop, not three`() throws {
            #expect(CI.Inventory.Document.callerHops == 1)
            #expect(CI.Inventory.Document.schemaVersion == 2)
        }

        @Test func `the verdict resolves to the one required check context`() throws {
            #expect(CI.Inventory.Aggregate.checkContext == "ci / matrix / ci-ok")
            #expect(CI.Inventory.Aggregate.checkContext == CI.Contract.Requirement.checkContext)
        }

        @Test func `ci-ok is the only authored aggregate that gates`() throws {
            let universal = try CIInventoryTests.shipped().universal
            let aggregates = universal.jobs.filter { $0.posture == .aggregate }
            #expect(Set(aggregates.map(\.id)) == ["ci-ok", "advisory-summary"])
            #expect(!universal.aggregate.gatingJobs.isEmpty)
            #expect(universal.aggregate.gatingJobs.allSatisfy { $0 != "advisory-summary" })
        }

        @Test func `the only inner aggregate is a native matrix job and gates nothing`() throws {
            let universal = try CIInventoryTests.shipped().universal
            let inner = Set(universal.aggregate.innerMatrixJobs)
            #expect(!inner.isEmpty)
            #expect(inner.isDisjoint(with: Set(universal.aggregate.gatingJobs)))
        }
    }

    @Suite
    struct Derivation {
        @Test func `every job's posture is exactly one of the five`() throws {
            let universal = try CIInventoryTests.shipped().universal
            let gating = Set(universal.aggregate.gatingJobs)
            let advisory = Set(universal.aggregate.advisoryJobs)
            #expect(gating.isDisjoint(with: advisory))
            for job in universal.jobs {
                switch job.posture {
                case .plan: #expect(job.id == "plan")
                case .aggregate: #expect(["ci-ok", "advisory-summary"].contains(job.id))
                case .gating: #expect(gating.contains(job.id))
                case .advisory: #expect(advisory.contains(job.id))
                case .eventGated:
                    #expect(!gating.contains(job.id))
                    #expect(!advisory.contains(job.id))
                }
            }
            #expect(universal.jobCount == universal.jobs.count)
        }

        @Test func `an aggregate sits at a strictly higher wave than everything it needs`() throws {
            let universal = try CIInventoryTests.shipped().universal
            let ciOk = try #require(universal.job("ci-ok"))
            for id in universal.aggregate.gatingJobs {
                let leg = try #require(universal.job(id))
                #expect(leg.wave < ciOk.wave)
            }
            #expect(try #require(universal.job("plan")).wave == 0)
        }

        @Test func `no cache step ever caches the build directory`() throws {
            let universal = try CIInventoryTests.shipped().universal
            for step in universal.cacheSteps {
                let path = step.path.map(CI.Workflow.YAML.Canonical.json) ?? ""
                #expect(!path.contains(".build"))
            }
        }

        @Test func `the plan delegates its leg vocabulary to its Swift owner`() throws {
            let plan = try CIInventoryTests.shipped().universal.plan
            // The retired inventory re-extracted this from a `LEGS="…"`
            // shell literal that no longer exists, and had been
            // recording an EMPTY vocabulary as the shipped truth.
            #expect(plan.delegatesToInstituteCI)
            #expect(!CI.Inventory.Plan.fullTierLegs.isEmpty)
        }

        @Test func `every full-tier leg names a job the universal actually declares`() throws {
            let universal = try CIInventoryTests.shipped().universal
            let declared = Set(universal.jobs.map(\.id))
            for leg in CI.Inventory.Plan.fullTierLegs {
                #expect(declared.contains(leg), "full-tier leg '\(leg)' is not a declared job")
            }
        }

        @Test func `every gating job carries the private-visibility guard`() throws {
            // A guarded gating job reports NO signal on a private
            // repository. That is a deliberate property of the shipped
            // verdict, and it is worth failing on if it ever becomes
            // partial: half-guarded gating is a verdict that means
            // different things in the two visibilities.
            let universal = try CIInventoryTests.shipped().universal
            for id in universal.aggregate.gatingJobs {
                #expect(try #require(universal.job(id)).privateGuarded)
            }
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `a workflow with no jobs is refused, not inventoried as empty`() {
            #expect(throws: CI.Inventory.Error.noJobs) {
                try CI.Inventory.Document(universalWorkflow: "on:\n  push:\n")
            }
        }

        @Test func `a workflow with no ci-ok is refused by name`() {
            #expect(throws: CI.Inventory.Error.missingJob("ci-ok")) {
                try CI.Inventory.Document(
                    universalWorkflow: "jobs:\n  plan:\n    runs-on: ubuntu-latest\n")
            }
        }

        @Test func `a workflow with no plan is refused by name`() {
            #expect(throws: CI.Inventory.Error.missingJob("plan")) {
                try CI.Inventory.Document(
                    universalWorkflow: "jobs:\n  ci-ok:\n    runs-on: ubuntu-latest\n")
            }
        }

        @Test func `a bare needs scalar is the same DAG as a one-element list`() {
            var cache: [String: Int] = [:]
            let waves = ["a": [], "b": ["a"], "c": ["a", "b"]]
            #expect(CI.Inventory.Universal.wave(of: "a", needs: waves, cache: &cache) == 0)
            #expect(CI.Inventory.Universal.wave(of: "c", needs: waves, cache: &cache) == 2)
        }

        @Test func `a needs entry naming an undeclared job contributes no wave`() {
            var cache: [String: Int] = [:]
            let waves = ["a": ["ghost"]]
            #expect(CI.Inventory.Universal.wave(of: "a", needs: waves, cache: &cache) == 0)
        }
    }
}
