import CI_Contract
import Testing

@testable import CI_Validation

/// `[BRANCH-PIN-001]` controls.
///
/// The fixture corpus proves the *detector* — it fires on a branch pin
/// and stays silent on versions, foreign orgs and commented-out
/// declarations. What the corpus cannot reach is the guard contract laid
/// on top: baseline suppression, the ruled `main` exception, and the
/// organization manifest the whole rule is scoped by. That is this
/// suite, and it is the Swift owner of
/// `.github/scripts/tests/test-validate-branch-pins.py`.
@Suite
struct CIValidationBranchPinsTests {
    static func pinnedManifest(_ requirement: String) -> String {
        """
        // swift-tools-version: 6.3
        import PackageDescription
        let package = Package(
            name: "fixture",
            dependencies: [
                .package(url: "https://github.com/swift-primitives/swift-pinned.git", \
        \(requirement)),
            ],
            targets: [.target(name: "Fixture")]
        )
        """
    }

    static func validator(baseline: String? = nil) -> CI.Validation.BranchPins {
        CI.Validation.BranchPins(
            organizationsFile: RepositoryUnderTest.organizationsFile,
            baselineFile: baseline
        )
    }

    @Suite
    struct `Baseline Contract` {
        @Test func `an unbaselined pin fires the rule`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#"branch: "develop""#),
                to: "Package.swift"
            )
            let findings = try CIValidationBranchPinsTests.validator()
                .findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["BRANCH-PIN-001"])
        }

        @Test func `a baselined pair reports as informational`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#"branch: "develop""#),
                to: "Package.swift"
            )
            repository.write(
                "# test baseline\nswift-primitives/consumer\t"
                    + "https://github.com/swift-primitives/swift-pinned.git\n",
                to: "baseline.tsv"
            )
            let findings =
                try CIValidationBranchPinsTests
                .validator(baseline: repository.path("baseline.tsv"))
                .findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["BRANCH-PIN-BASELINE"])
        }

        @Test func `a populated baseline that does not name this pin still fires`() throws {
            // The guard's own positive control: a broken baseline filter
            // must not silently admit new pins.
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#"branch: "develop""#),
                to: "Package.swift"
            )
            repository.write(
                "swift-primitives/consumer\t"
                    + "https://github.com/swift-primitives/swift-unrelated.git\n",
                to: "baseline.tsv"
            )
            let findings =
                try CIValidationBranchPinsTests
                .validator(baseline: repository.path("baseline.tsv"))
                .findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["BRANCH-PIN-001"])
        }

        @Test func `the same url baselined by a different repository does not suppress`() throws {
            // The ledger's key is the (repository, url) pair. The same
            // dependency pinned by someone else is a new pin.
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#"branch: "develop""#),
                to: "Package.swift"
            )
            repository.write(
                "swift-primitives/other-consumer\t"
                    + "https://github.com/swift-primitives/swift-pinned.git\n",
                to: "baseline.tsv"
            )
            let findings =
                try CIValidationBranchPinsTests
                .validator(baseline: repository.path("baseline.tsv"))
                .findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["BRANCH-PIN-001"])
        }

        @Test func `a missing baseline file is an empty baseline`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#"branch: "develop""#),
                to: "Package.swift"
            )
            let findings =
                try CIValidationBranchPinsTests
                .validator(baseline: repository.path("does-not-exist.tsv"))
                .findings(in: repository.subject)
            #expect(findings.map(\.rule) == ["BRANCH-PIN-001"])
        }
    }

    /// The ruled exception (principal, 2026-07-30;
    /// `swift-standards/swift-mailgun-standard#13`): `branch: "main"` on
    /// an Institute dependency passes with no baseline entry. **Exact
    /// match on `main`, not a general amnesty.**
    @Suite
    struct `Main Branch Exception` {
        @Test func `a main pin on an Institute dependency is silent`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#"branch: "main""#),
                to: "Package.swift"
            )
            #expect(
                try CIValidationBranchPinsTests.validator()
                    .findings(in: repository.subject).isEmpty
            )
        }

        @Test func `the legacy main spelling is silent too`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#".branch("main")"#),
                to: "Package.swift"
            )
            #expect(
                try CIValidationBranchPinsTests.validator()
                    .findings(in: repository.subject).isEmpty
            )
        }

        @Test func `any other branch name still fires`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                CIValidationBranchPinsTests.pinnedManifest(#".branch("release/1.0")"#),
                to: "Package.swift"
            )
            #expect(
                try CIValidationBranchPinsTests.validator()
                    .findings(in: repository.subject).map(\.rule) == ["BRANCH-PIN-001"]
            )
        }
    }

    @Suite
    struct Scope {
        @Test func `a branch pin on a non-Institute dependency is out of scope`() throws {
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                """
                // swift-tools-version: 6.3
                import PackageDescription
                let package = Package(
                    name: "fixture",
                    dependencies: [
                        .package(url: "https://github.com/apple/swift-nio.git", branch: "dev"),
                    ]
                )
                """,
                to: "Package.swift"
            )
            #expect(
                try CIValidationBranchPinsTests.validator()
                    .findings(in: repository.subject).isEmpty
            )
        }

        @Test func `a commented out declaration is invisible`() throws {
            // Comments are stripped string-aware and nesting-aware before
            // any call window is cut, so a declaration a reader can see
            // but the compiler cannot is not a pin.
            let repository = TemporaryRepository(repository: "swift-primitives/consumer")
            repository.write(
                """
                // swift-tools-version: 6.3
                let package = Package(
                    dependencies: [
                        // .package(url: "https://github.com/swift-primitives/x.git", \
                branch: "dev"),
                        /* .package(url: "https://github.com/swift-primitives/y.git", \
                branch: "dev"), /* nested */ */
                    ]
                )
                """,
                to: "Package.swift"
            )
            #expect(
                try CIValidationBranchPinsTests.validator()
                    .findings(in: repository.subject).isEmpty
            )
        }

        @Test func `a url containing a double slash is not read as a comment`() throws {
            // Every https URL in the file contains `//`. Stripping that
            // as a line comment would silence the whole rule.
            let stripped = CI.Validation.BranchPins.strippingComments(
                #".package(url: "https://github.com/swift-primitives/x.git", branch: "dev")"#
            )
            #expect(stripped.contains("https://github.com/swift-primitives/x.git"))
        }

        @Test func `only root manifests are scanned`() {
            #expect(CI.Validation.BranchPins.isRootManifestName("Package.swift"))
            #expect(CI.Validation.BranchPins.isRootManifestName("Package@swift-6.3.swift"))
            #expect(!CI.Validation.BranchPins.isRootManifestName("PackageDescription.swift"))
            #expect(!CI.Validation.BranchPins.isRootManifestName("Package@swift-next.swift"))
        }

        @Test func `only a two segment github url names an organization`() {
            let organization = CI.Validation.BranchPins.gitHubOrganization
            #expect(organization("https://github.com/swift-primitives/x") == "swift-primitives")
            #expect(organization("https://github.com/swift-primitives/x.git") == "swift-primitives")
            #expect(organization("https://github.com/swift-primitives/x/y") == nil)
            #expect(organization("https://gitlab.com/swift-primitives/x") == nil)
        }
    }

    @Suite
    struct `Environment Defect` {
        @Test func `an unreadable organization manifest is a defect, never an empty set`() {
            // An empty organization set would make every subject silently
            // clean — the inert-gate failure this contract's exit-2 class
            // exists to prevent.
            let repository = TemporaryRepository()
            repository.write("dependencies: []", to: "Package.swift")
            #expect(throws: CI.Validation.EnvironmentDefect.self) {
                try CI.Validation.BranchPins(organizationsFile: "/nowhere/orgs.yaml")
                    .findings(in: repository.subject)
            }
        }

        @Test func `the canonical manifest carries the Institute organizations`() throws {
            let organizations = try CI.Validation.BranchPins.Organizations.read(
                at: RepositoryUnderTest.organizationsFile
            )
            #expect(organizations.contains("swift-institute"))
            #expect(organizations.contains("swift-primitives"))
            #expect(!organizations.contains("apple"))
        }
    }
}
