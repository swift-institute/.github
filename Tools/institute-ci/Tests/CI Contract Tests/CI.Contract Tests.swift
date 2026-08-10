import CI_Contract
import Testing

@Suite
struct CIContractPlanTests {
    static let currentNightlyException = CI.Contract.NightlyException(
        image: "swiftlang/swift@sha256:f577f95edfb85cf3bdc45eb0badaab09239de5c86c69b3b6d594cc62916c0a7d",
        upstreamIssue: "https://github.com/swiftlang/swift/issues/90275",
        recheck: "2026-09-14")

    @Test func mainNightlyExceptionRefusesMutableOrMalformedIdentity() throws {
        #expect(try Self.currentNightlyException.disposition(
            today: "2026-08-09", subjectRepository: "swift-standards/swift-fips-180-4")
            == .active)
        // Malformed fields refuse EVERYWHERE, owner and fleet alike —
        // authoring defects are not calendar events.
        for subject in [CI.Contract.NightlyException.owner, "o/r"] {
            #expect(throws: CI.Contract.NightlyException.Error.image("swiftlang/swift:nightly-main-jammy")) {
                try CI.Contract.NightlyException(
                    image: "swiftlang/swift:nightly-main-jammy",
                    upstreamIssue: "https://github.com/swiftlang/swift/issues/90275",
                    recheck: "2026-09-14").disposition(today: "2026-08-09", subjectRepository: subject)
            }
        }
    }

    /// The localized forcing function (ruled 2026-08-10, .github#488): an
    /// expired advisory-class exception fails closed on the owner
    /// repository alone — the positive control proving expiry still forces
    /// a ruling — and deschedules, with the typed record, everywhere else.
    @Test func expiredNightlyExceptionFailsOwnerAndDeschedulesFleet() throws {
        #expect(throws: CI.Contract.NightlyException.Error.expired(recheck: "2026-09-14", today: "2026-09-15")) {
            try Self.currentNightlyException.disposition(
                today: "2026-09-15",
                subjectRepository: CI.Contract.NightlyException.owner)
        }
        #expect(try Self.currentNightlyException.disposition(
            today: "2026-09-15", subjectRepository: "swift-standards/swift-fips-180-4")
            == .expired(recheck: "2026-09-14", today: "2026-09-15"))
    }

    /// The class is derived from the leg's mechanical facts, never
    /// authored: the classified leg must not be gating (ci-ok needs).
    /// Guards the class-gaming route the adversarial review named — if the
    /// classified leg ever becomes gating, every disposition refuses.
    @Test func nightlyExceptionClassifiesAnAdvisoryLegOnly() throws {
        #expect(!CI.Contract.NightlyException.classifiedLeg.gating)
        #expect(CI.Contract.Leg("linux-release").gating)
    }

    /// Expiry deschedules typed, not silent: the leg leaves `legs`, the
    /// record names it with its reason, and a leg the tier never selected
    /// is absent rather than descheduled.
    @Test func expiredNightlyDispositionDeschedulesTheClassifiedLeg() throws {
        let full = try CI.Contract.Plan(
            forcedTier: "full", ref: "refs/heads/x", event: "push",
            lintBundle: "standards",
            nightlyDisposition: .expired(recheck: "2026-09-14", today: "2026-09-15"))
        #expect(!full.legs.map(\.id).contains("linux-nightly"))
        #expect(full.descheduled == [
            .init(leg: .init("linux-nightly"), reason: .nightlyExceptionExpired)
        ])
        #expect(full.gating.map(\.id).contains("linux-release"))

        // The build tier never schedules linux-nightly, so there is
        // nothing to deschedule and the record stays empty.
        let build = try CI.Contract.Plan(
            ref: "refs/heads/x", event: "push", lintBundle: "standards",
            nightlyDisposition: .expired(recheck: "2026-09-14", today: "2026-09-15"))
        #expect(build.descheduled.isEmpty)
        #expect(build.legs.map(\.id) == ["format", "lint", "swift-linter", "linux-release", "linux-6-4"])
    }

    /// The floor's image is `swift:<floor>` and nothing else — the terminal
    /// state, and the one a removal of the exception restores.
    @Test func releaseFloorWithoutAnExceptionIsTheOfficialImage() throws {
        #expect(
            try CI.Contract.ReleaseFloorException.resolve(
                swiftVersion: "6.4", exception: nil, today: "2026-08-09") == "swift:6.4")
    }

    /// swift-institute/.github#491: the substitute image is admissible only
    /// as an exact digest, naming the release whose arrival retires it, with
    /// a recheck date inside the RC/stable boundary and not yet past.
    @Test func releaseFloorExceptionRefusesEveryLooseIdentity() throws {
        let valid = CI.Contract.ReleaseFloorException(
            swiftVersion: "6.4",
            image:
                "swiftlang/swift@sha256:28424ece0fa465ad87d8cf55be685fc89f8286e91e86ebb7503418561c0a71d1",
            upstreamRelease: "https://github.com/swiftlang/swift/releases/tag/swift-6.4-RELEASE",
            recheck: "2026-09-09")
        try valid.validate(today: "2026-08-09")
        #expect(
            try CI.Contract.ReleaseFloorException.resolve(
                swiftVersion: "6.4", exception: valid, today: "2026-08-09") == valid.image)

        // The tag the pre-floor workflow used: an existing image, but a
        // mutable identity, which is exactly what this class refuses.
        #expect(
            throws: CI.Contract.ReleaseFloorException.Error.image(
                "swiftlang/swift:nightly-6.4.x-jammy")
        ) {
            try CI.Contract.ReleaseFloorException(
                swiftVersion: "6.4",
                image: "swiftlang/swift:nightly-6.4.x-jammy",
                upstreamRelease:
                    "https://github.com/swiftlang/swift/releases/tag/swift-6.4-RELEASE",
                recheck: "2026-09-09").validate(today: "2026-08-09")
        }

        // An upstream coordinate for a different release cannot justify
        // substituting for THIS floor.
        #expect(
            throws: CI.Contract.ReleaseFloorException.Error.upstreamRelease(
                "https://github.com/swiftlang/swift/releases/tag/swift-6.3-RELEASE")
        ) {
            try CI.Contract.ReleaseFloorException(
                swiftVersion: "6.4",
                image:
                    "swiftlang/swift@sha256:28424ece0fa465ad87d8cf55be685fc89f8286e91e86ebb7503418561c0a71d1",
                upstreamRelease:
                    "https://github.com/swiftlang/swift/releases/tag/swift-6.3-RELEASE",
                recheck: "2026-09-09").validate(today: "2026-08-09")
        }

        // Past the RC/stable boundary: refused at authoring time, not merely
        // when it eventually expires.
        #expect(
            throws: CI.Contract.ReleaseFloorException.Error.beyondBoundary(
                recheck: "2026-10-01", boundary: "2026-09-09")
        ) {
            try CI.Contract.ReleaseFloorException(
                swiftVersion: "6.4",
                image:
                    "swiftlang/swift@sha256:28424ece0fa465ad87d8cf55be685fc89f8286e91e86ebb7503418561c0a71d1",
                upstreamRelease:
                    "https://github.com/swiftlang/swift/releases/tag/swift-6.4-RELEASE",
                recheck: "2026-10-01").validate(today: "2026-08-09")
        }

        // Expired: the run fails closed rather than pulling on unexamined.
        #expect(
            throws: CI.Contract.ReleaseFloorException.Error.expired(
                recheck: "2026-09-09", today: "2026-09-10")
        ) {
            try CI.Contract.ReleaseFloorException.resolve(
                swiftVersion: "6.4", exception: valid, today: "2026-09-10")
        }

        #expect(throws: CI.Contract.ReleaseFloorException.Error.swiftVersion("main")) {
            try CI.Contract.ReleaseFloorException(
                swiftVersion: "main",
                image:
                    "swiftlang/swift@sha256:28424ece0fa465ad87d8cf55be685fc89f8286e91e86ebb7503418561c0a71d1",
                upstreamRelease:
                    "https://github.com/swiftlang/swift/releases/tag/swift-main-RELEASE",
                recheck: "2026-09-09").validate(today: "2026-08-09")
        }
    }

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

    /// The descheduled record is the audited third state: a descheduled leg
    /// must have skipped, and it can never be gating.
    @Test
    func descheduledLegsAreAuditedNotAssumed() {
        var results = needs(["format": "success", "lint": "success",
                             "swift-linter": "success", "linux-release": "success"])
        let gating = ["format", "lint", "swift-linter", "linux-release"]
        let clean = CI.Contract.AggregateVerdict(
            planResult: "success", results: results, gating: gating,
            subjectRepository: "o/r", subjectSha: "abc", tier: "full",
            requireFullTier: false, descheduled: ["linux-nightly"])
        #expect(clean.pass)

        // The record and the execution graph disagreeing is a failure.
        results["linux-nightly"] = "success"
        let ran = CI.Contract.AggregateVerdict(
            planResult: "success", results: results, gating: gating,
            subjectRepository: "o/r", subjectSha: "abc", tier: "full",
            requireFullTier: false, descheduled: ["linux-nightly"])
        #expect(!ran.pass)
        #expect(ran.findings.contains(
            .descheduledLegRan(job: "linux-nightly", result: "success")))

        // A gating leg can never be accounted for by descheduling.
        let gamed = CI.Contract.AggregateVerdict(
            planResult: "success",
            results: needs(["format": "success", "lint": "success",
                            "swift-linter": "success", "linux-release": "success"]),
            gating: gating,
            subjectRepository: "o/r", subjectSha: "abc", tier: "full",
            requireFullTier: false, descheduled: ["windows-release"])
        #expect(!gamed.pass)
        #expect(gamed.findings.contains(
            .descheduledGatingLeg(job: "windows-release")))
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
