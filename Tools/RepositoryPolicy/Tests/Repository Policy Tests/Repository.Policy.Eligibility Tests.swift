import Repository_Policy
import Testing

/// The F14 wave's eligibility predicate, hoisted out of shell
/// (swift-institute/.github#404, F16; predicate proved at #394 comment
/// 5205766701).
///
/// The corpus below is not illustrative: every row is a repository the F14
/// wave actually measured, and the negative controls are the exact two
/// directions the wave proved the naive predicates wrong in.
@Suite
struct RepositoryPolicyEligibilityTests {
    // MARK: Positive — the ordinary fleet leaf

    @Test
    func rootManifestWithNoExceptionIsEligible() {
        let verdict = Repository.Policy.Eligibility.verdict(
            .init(repository: "swift-primitives/swift-percent-primitives",
                  rootManifest: .present))
        #expect(verdict == .eligible)
        #expect(verdict.isEligible)
    }

    // MARK: Negative control 1 — the destructive direction
    //
    // A `Package.swift`-only predicate would have overwritten bespoke CI
    // here (100 lines → 26). The manifest is present; the verdict must
    // still not be `.eligible`.

    @Test
    func issuesIsExcludedDespiteCarryingARootManifest() {
        let verdict = Repository.Policy.Eligibility.verdict(
            .init(repository: "swift-institute/Issues", rootManifest: .present))
        guard case .bespoke(let exception) = verdict else {
            Issue.record("expected .bespoke, got \(verdict)")
            return
        }
        #expect(exception.repository == "swift-institute/Issues")
        #expect(!exception.reason.isEmpty)
        #expect(!verdict.isEligible)
    }

    /// GitHub repository names are case-insensitive, so a case-sensitive
    /// membership test would miss the exception and converge bespoke CI
    /// away. This near-miss must still be excluded.
    @Test
    func theExceptionSetMatchesCaseInsensitively() {
        let verdict = Repository.Policy.Eligibility.verdict(
            .init(repository: "swift-institute/issues", rootManifest: .present))
        #expect(!verdict.isEligible)
    }

    /// …but only on the whole coordinate. A different repository whose
    /// name merely contains an exception's name is NOT excluded — without
    /// this control, a `contains`-shaped predicate would silently protect
    /// (and therefore never converge) an unrelated leaf.
    @Test
    func aRepositoryContainingAnExceptionNameIsStillEligible() {
        #expect(
            Repository.Policy.Eligibility.verdict(
                .init(repository: "swift-institute/Issues-archive",
                      rootManifest: .present)) == .eligible)
        #expect(
            Repository.Policy.Eligibility.verdict(
                .init(repository: "swift-foundations/Issues",
                      rootManifest: .present)) == .eligible)
    }

    // MARK: Negative control 2 — excluded by the manifest term

    @Test
    func skillsAndCclspAreExcludedByTheManifestTerm() {
        for repository in ["swift-institute/Skills", "swift-institute/cclsp"] {
            #expect(
                Repository.Policy.Eligibility.verdict(
                    .init(repository: repository, rootManifest: .absent))
                    == .noManifest,
                "\(repository)")
        }
    }

    /// The manifest term is evaluated first, so an exception-listed
    /// repository with no manifest reports the reason it is actually out.
    /// The exception is still there to catch it if it ever gains one.
    @Test
    func skillsReportsNoManifestNowAndBespokeIfItEverGainsOne() {
        #expect(
            Repository.Policy.Eligibility.verdict(
                .init(repository: "swift-institute/Skills", rootManifest: .absent))
                == .noManifest)
        #expect(
            !Repository.Policy.Eligibility.verdict(
                .init(repository: "swift-institute/Skills", rootManifest: .present))
                .isEligible)
    }

    /// The control repository for the manifest probe itself: this very
    /// repository carries no root `Package.swift`.
    @Test
    func theControlPlaneRepositoryIsNotAWaveSubject() {
        #expect(
            Repository.Policy.Eligibility.verdict(
                .init(repository: "swift-institute/.github", rootManifest: .absent))
                == .noManifest)
    }

    // MARK: Negative control 3 — the omission direction
    //
    // The five unarchived repositories that carry a root `Package.swift`
    // and no `ci.yml`. A `ci.yml`-keyed wave skips every one; the correct
    // predicate admits all five, because it never consults `ci.yml`.

    @Test
    func theFiveManifestOnlyLeavesAreIncluded() {
        let created = [
            "swift-foundations/swift-epub-render",
            "swift-foundations/swift-testing-extras",
            "swift-foundations/swift-sql-postgres-native",
            "swift-institute/swift-institute.org",
            "swift-institute/swift-xml-printer",
        ]
        for repository in created {
            #expect(
                Repository.Policy.Eligibility.verdict(
                    .init(repository: repository, rootManifest: .present))
                    == .eligible,
                "\(repository)")
        }
    }

    // MARK: The exception set as data

    @Test
    func everyExceptionNamesItsRulingAndAFullCoordinate() {
        #expect(!Repository.Policy.Eligibility.bespoke.isEmpty)
        for exception in Repository.Policy.Eligibility.bespoke {
            #expect(exception.repository.contains("/"), "\(exception.repository)")
            #expect(exception.reason.contains("swift-institute/.github#"),
                    "\(exception.repository) names no durable ruling coordinate")
        }
    }

    @Test
    func theExceptionSetHasNoDuplicateCoordinates() {
        let names = Repository.Policy.Eligibility.bespoke.map(\.repository)
        #expect(names.count == Set(names.map { $0.lowercased() }).count)
    }

    @Test
    func lookupReturnsNilForANonException() {
        #expect(
            Repository.Policy.Eligibility
                .exception("swift-primitives/swift-percent-primitives") == nil)
    }
}
