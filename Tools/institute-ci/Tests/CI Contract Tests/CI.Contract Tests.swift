import CI_Contract
import Testing

@Suite
struct CIContractPlanTests {
    @Test
    func ordinaryPushSelectsBuildTierWithLinuxPrimary() throws {
        let plan = try CI.Contract.Plan(
            ref: "refs/heads/feature", event: "push", lintBundle: "standards")
        #expect(plan.tier == .build)
        #expect(plan.legs.map(\.id) == ["format", "lint", "swift-linter", "linux-release", "linux-6-4"])
        #expect(plan.gating.map(\.id) == ["format", "lint", "swift-linter", "linux-release"])
    }

    @Test
    func tagRefAndDispatchAndMainForceFullTier() throws {
        for (ref, event) in [("refs/tags/1.0.0", "push"),
                             ("refs/heads/x", "workflow_dispatch"),
                             ("refs/heads/main", "push")] {
            let plan = try CI.Contract.Plan(ref: ref, event: event, lintBundle: "institute")
            #expect(plan.tier == .full, "\(ref)/\(event)")
        }
    }

    @Test
    func commitTokensSteerTier() throws {
        #expect(try CI.Contract.Plan(
            ref: "refs/heads/x", headMessage: "wip [ci full]", event: "push",
            lintBundle: "standards").tier == .full)
        #expect(try CI.Contract.Plan(
            ref: "refs/heads/x", headMessage: "wip [ci build]", event: "workflow_dispatch",
            lintBundle: "standards").tier == .build)
    }

    @Test
    func retiredLintTierRefuses() {
        #expect(throws: CI.Contract.Plan.Error.retiredLintTier) {
            try CI.Contract.Plan(
                forcedTier: "lint", ref: "refs/heads/x", event: "push",
                lintBundle: "standards")
        }
    }

    @Test
    func platformSupportValidation() {
        #expect(throws: CI.Contract.Plan.Error.invalidPlatformFamily("mac")) {
            try CI.Contract.Plan(
                ref: "refs/heads/x", event: "push", platformSupport: "mac",
                lintBundle: "standards")
        }
        #expect(throws: CI.Contract.Plan.Error.duplicatePlatformFamily("linux")) {
            try CI.Contract.Plan(
                ref: "refs/heads/x", event: "push", platformSupport: "linux,linux",
                lintBundle: "standards")
        }
        #expect(throws: CI.Contract.Plan.Error.trailingEmptyPlatformFamily("linux,")) {
            try CI.Contract.Plan(
                ref: "refs/heads/x", event: "push", platformSupport: "linux,",
                lintBundle: "standards")
        }
        #expect(throws: CI.Contract.Plan.Error.invalidPlatformFamily("")) {
            try CI.Contract.Plan(
                ref: "refs/heads/x", event: "push", platformSupport: ",linux",
                lintBundle: "standards")
        }
    }

    @Test
    func buildTierPrimarySelectionFollowsPriority() throws {
        #expect(try CI.Contract.Plan(
            ref: "refs/heads/x", event: "push", platformSupport: "windows,apple",
            lintBundle: "standards").legs.map(\.id).contains("windows-release"))
        let appleOnly = try CI.Contract.Plan(
            ref: "refs/heads/x", event: "push", platformSupport: "apple",
            lintBundle: "standards")
        #expect(appleOnly.legs.map(\.id) == ["format", "lint", "swift-linter", "macos-release"])
    }

    @Test
    func fullTierPlatformFilterNarrowsLegs() throws {
        let plan = try CI.Contract.Plan(
            forcedTier: "full", ref: "refs/heads/x", event: "push",
            platformSupport: "linux", lintBundle: "standards")
        #expect(!plan.legs.map(\.id).contains("macos-release"))
        #expect(!plan.legs.map(\.id).contains("windows-release"))
        #expect(!plan.legs.map(\.id).contains("apple-simulator-build"))
        #expect(plan.legs.map(\.id).contains("linux-nightly"))
        #expect(plan.legs.map(\.id).contains("lint-yaml"))
    }

    @Test
    func primitivesBundleAppendsAdvisoryLegsInBothTiers() throws {
        for tier in ["build", "full"] {
            let plan = try CI.Contract.Plan(
                forcedTier: tier, ref: "refs/heads/x", event: "push",
                lintBundle: "primitives")
            #expect(plan.legs.map(\.id).contains("embedded"), Comment(rawValue: tier))
            #expect(!plan.gating.map(\.id).contains("embedded"), Comment(rawValue: tier))
        }
    }

    @Test
    func invalidLintBundleRefuses() {
        #expect(throws: CI.Contract.Plan.Error.invalidLintBundle("web")) {
            try CI.Contract.Plan(ref: "refs/heads/x", event: "push", lintBundle: "web")
        }
    }
}

@Suite
struct CIContractAggregateTests {
    static let participants = ["macos-release", "linux-release", "windows-release",
                               "format", "lint", "swift-linter"]

    func needs(_ overrides: [String: String]) -> [String: String] {
        var results: [String: String] = [:]
        for job in Self.participants { results[job] = overrides[job] ?? "skipped" }
        return results
    }

    @Test
    func selectedTierPasses() {
        let verdict = CI.Contract.AggregateVerdict(
            planResult: "success",
            results: needs(["format": "success", "lint": "success",
                            "swift-linter": "success", "linux-release": "success"]),
            gating: ["format", "lint", "swift-linter", "linux-release"],
            subjectRepository: "o/r", subjectSha: "abc", tier: "build",
            requireFullTier: false)
        #expect(verdict.pass)
        #expect(verdict.built == ["linux-release"])
    }

    @Test
    func skippedGatingLegFails() {
        let verdict = CI.Contract.AggregateVerdict(
            planResult: "success",
            results: needs(["format": "success", "lint": "success",
                            "swift-linter": "skipped", "linux-release": "success"]),
            gating: ["format", "lint", "swift-linter", "linux-release"],
            subjectRepository: "o/r", subjectSha: "abc", tier: "build",
            requireFullTier: false)
        #expect(!verdict.pass)
        #expect(verdict.findings.contains(
            .selectedLegNotSuccessful(job: "swift-linter", result: "skipped")))
    }

    @Test
    func unselectedLegThatRanFails() {
        let verdict = CI.Contract.AggregateVerdict(
            planResult: "success",
            results: needs(["format": "success", "lint": "success",
                            "swift-linter": "success", "linux-release": "success",
                            "macos-release": "success"]),
            gating: ["format", "lint", "swift-linter", "linux-release"],
            subjectRepository: "o/r", subjectSha: "abc", tier: "build",
            requireFullTier: false)
        #expect(!verdict.pass)
        #expect(verdict.findings.contains(
            .unselectedLegRan(job: "macos-release", result: "success")))
    }

    @Test
    func planFailureEmptyGatingEmptySubjectAllFail() {
        let verdict = CI.Contract.AggregateVerdict(
            planResult: "failure", results: needs([:]), gating: [],
            subjectRepository: "", subjectSha: "", tier: "",
            requireFullTier: false)
        #expect(!verdict.pass)
        #expect(verdict.findings.contains(.planDidNotSucceed(result: "failure")))
        #expect(verdict.findings.contains(.emptyGating))
        #expect(verdict.findings.contains(.emptySubject))
        #expect(verdict.findings.contains(.nothingBuilt))
    }

    @Test
    func mainRequiresFullTier() {
        let verdict = CI.Contract.AggregateVerdict(
            planResult: "success",
            results: needs(["format": "success", "lint": "success",
                            "swift-linter": "success", "linux-release": "success"]),
            gating: ["format", "lint", "swift-linter", "linux-release"],
            subjectRepository: "o/r", subjectSha: "abc", tier: "build",
            requireFullTier: true)
        #expect(!verdict.pass)
        #expect(verdict.findings.contains(.fullTierRequired(got: "build")))
    }

    @Test
    func lintOnlySuccessWithoutBuildFails() {
        let verdict = CI.Contract.AggregateVerdict(
            planResult: "success",
            results: needs(["format": "success", "lint": "success",
                            "swift-linter": "success"]),
            gating: ["format", "lint", "swift-linter"],
            subjectRepository: "o/r", subjectSha: "abc", tier: "build",
            requireFullTier: false)
        #expect(!verdict.pass)
        #expect(verdict.findings.contains(.nothingBuilt))
    }

    @Test
    func requirementTablePreservesCheckContext() {
        #expect(CI.Contract.Requirement.checkContext == "ci / matrix / ci-ok")
        let table = CI.Contract.Requirement.table(
            participants: ["plan"] + Self.participants,
            gating: [CI.Contract.Leg("format"), CI.Contract.Leg("linux-release")])
        #expect(table.count == 6)
        #expect(table.first { $0.job == "format" }?.expectation == .success)
        #expect(table.first { $0.job == "macos-release" }?.expectation == .skipped)
    }
}
