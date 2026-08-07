import CI_Contract
import CI_Validation
import Foundation
import Testing

/// The fixture corpus is the differential gate's subject and covers the
/// registered shapes. These are the propositions the corpus cannot state
/// directly: that the `[CI-059]` obligation genuinely *inverts* on the
/// hosting organization, that the exemption gate admits one class and no
/// other, and that diagnostic precedence needs its proof rather than a
/// heuristic.
@Suite
struct CIValidationThinCallersTests {
    /// A subject built from text written into a scratch tree, since every
    /// predicate reads a real repository layout.
    static func subject(
        _ repository: String, ci: String? = nil, files: [String: String] = [:]
    ) throws -> (CI.Validation.Subject, URL) {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "c3-\(UUID().uuidString)")
        var contents = files
        contents["Package.swift"] = files["Package.swift"] ?? "// swift-tools-version: 6.3\n"
        if let ci { contents[".github/workflows/ci.yml"] = ci }
        for (path, text) in contents {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return (CI.Validation.Subject(repository: repository, root: root.path), root)
    }

    static func findings(
        _ repository: String, ci: String? = nil, files: [String: String] = [:]
    ) throws -> [CI.Validation.Finding] {
        let (subject, root) = try subject(repository, ci: ci, files: files)
        defer { try? FileManager.default.removeItem(at: root) }
        return try CI.Validation.ThinCallers().findings(in: subject)
    }

    static let inheritCaller = """
        name: CI

        on:
          push:
            branches:
              - main

        jobs:
          ci:
            uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
            secrets: inherit
        """

    static let explicitCaller = """
        name: CI

        on:
          push:
            branches:
              - main

        jobs:
          ci:
            uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
            secrets:
              PRIVATE_REPO_TOKEN: ${{ secrets.PRIVATE_REPO_TOKEN }}
              SWIFT_INSTITUTE_BOT_APP_CLIENT_ID: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_CLIENT_ID }}
              SWIFT_INSTITUTE_BOT_APP_ID: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_ID }}
              SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY }}
        """

    // MARK: - The [CI-059] inversion

    /// The same two callers, swapped by hosting organization. This is the
    /// whole of `[CI-059]`'s sub-org caveat: `inherit` is correct in a
    /// layer org and wrong in a sub-org, because the sub-org's hop is
    /// cross-org and `inherit` silently delivers no org secrets there
    /// (`[CI-109]`). A validator that got this backwards would still pass
    /// half the corpus.
    @Test
    func theSecretObligationInvertsOnTheHostingOrganization() throws {
        #expect(try Self.findings("swift-standards/swift-x", ci: Self.inheritCaller).isEmpty)
        #expect(try Self.findings("swift-iso/swift-x", ci: Self.explicitCaller).isEmpty)

        let inheritInSubOrganization = try Self.findings(
            "swift-iso/swift-x", ci: Self.inheritCaller)
        #expect(inheritInSubOrganization.map(\.rule.rawValue) == ["CI-059"])
        #expect(inheritInSubOrganization[0].message.hasPrefix("[cross-org-inherit]"))

        let explicitInLayerOrganization = try Self.findings(
            "swift-standards/swift-x", ci: Self.explicitCaller)
        #expect(explicitInLayerOrganization.map(\.rule.rawValue) == ["CI-059"])
        #expect(explicitInLayerOrganization[0].message.hasPrefix("[same-org-explicit]"))
    }

    /// The credential set is closed in both directions: a name missing
    /// fires, and a name beyond it fires. Both can fire on one job.
    @Test
    func theCrossOrganizationSetIsClosedInBothDirections() throws {
        let caller = Self.explicitCaller
            .replacingOccurrences(
                of: "      SWIFT_INSTITUTE_BOT_APP_ID: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_ID }}\n",
                with: "")
            + "\n      EXTRA_TOKEN: ${{ secrets.EXTRA_TOKEN }}"
        let findings = try Self.findings("swift-ietf/swift-x", ci: caller)
        let classes = findings.map { $0.message.prefix { $0 != "]" } + "]" }
        #expect(classes == ["[cross-org-missing-names]", "[cross-org-extra-names]"])
        #expect(findings[0].message.contains("SWIFT_INSTITUTE_BOT_APP_ID"))
        #expect(findings[1].message.contains("EXTRA_TOKEN"))
    }

    /// An exemption admits exactly one class in exactly one file. The
    /// admitted shape is reported under `CI-059-EXEMPT`, which the
    /// aggregation layer does not count; the near-miss — the same
    /// repository, a *different* class — still fires as `CI-059`.
    ///
    /// The exemption is fixture-scoped by construction: its repository is
    /// the harness's reporting owner, which no production sweep passes.
    @Test
    func anExemptionAdmitsOneClassAndSuppressesNothingElse() throws {
        let admitted = try Self.findings(
            "swift-institute-test/swift-exempt-explicit-caller", ci: Self.explicitCaller)
        #expect(admitted.map(\.rule.rawValue) == ["CI-059-EXEMPT"])

        // Same repository, same file — but omission, not explicit
        // forwarding. A different class, so the exemption does not reach
        // it.
        let nearMiss = try Self.findings(
            "swift-institute-test/swift-exempt-explicit-caller",
            ci: Self.inheritCaller.replacingOccurrences(of: "    secrets: inherit", with: ""))
        #expect(nearMiss.map(\.rule.rawValue) == ["CI-059"])
        #expect(nearMiss[0].message.hasPrefix("[same-org-omitted]"))
    }

    // MARK: - File-level carve-out

    /// A workflow declaring `workflow_call:` *is* a reusable, and every
    /// rule here constrains callers. Tool-host packages ([GH-REPO-077])
    /// carry action refs and inline steps on purpose.
    @Test
    func aReusableIsExemptFromEveryRule() throws {
        let reusable = """
            name: Tool
            on:
              workflow_call:
            jobs:
              build:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        #expect(try Self.findings("swift-standards/swift-x", ci: reusable).isEmpty)
    }

    // MARK: - [CI-030]

    /// The discriminator is the `.github/.github/workflows/` double
    /// infix. A third-party action pinned at a tag is `[CI-107]`
    /// discipline, not a `[CI-030]` violation, and must not fire.
    @Test
    func onlyIntraInstituteReferencesAreHeldToTheMainPin() throws {
        let caller = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@v1.0.0
                secrets: inherit
              other:
                uses: some-vendor/some-repo/.github/workflows/thing.yml@v3
            """
        let pins = try Self.findings("swift-standards/swift-x", ci: caller)
            .filter { $0.rule.rawValue == "CI-030" }
        #expect(pins.count == 1)
        #expect(pins[0].message.contains("swift-standards/.github/.github/workflows/swift-ci.yml@v1.0.0"))
        #expect(!pins[0].message.contains("some-vendor"))
    }

    // MARK: - Diagnostic precedence

    /// When every job is inline and none delegates, the missing-reusable
    /// finding is the root: repairing it necessarily removes those jobs'
    /// `runs-on:` and `steps:`. Reporting all three describes one repair
    /// three times, so the two secondaries are omitted.
    @Test
    func theMissingReusableRootSupersedesTheInlineDiagnostics() throws {
        let allInline = """
            name: CI
            on:
              push:
                branches:
                  - main
            jobs:
              build:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        let findings = try Self.findings("swift-standards/swift-x", ci: allInline)
        #expect(findings.count == 1)
        #expect(findings[0].message.contains("does not reference any reusable"))
    }

    /// A *mixed* workflow keeps all three. The precedence proof is not a
    /// heuristic about how many findings there are: with one delegating
    /// job present, removing the inline job is a separate repair from
    /// adding a caller, so the diagnostics are independent again.
    @Test
    func aMixedWorkflowKeepsEveryDiagnostic() throws {
        let mixed = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                secrets: inherit
              extra:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        let messages = try Self.findings("swift-standards/swift-x", ci: mixed)
            .filter { $0.rule.rawValue == "GH-REPO-074" }
            .map(\.message)
        #expect(messages.count == 2)
        #expect(messages.contains { $0.contains("inline `runs-on:`") })
        #expect(messages.contains { $0.contains("inline `steps:`") })
    }

    /// An unparseable workflow must still be diagnosed. Reporting nothing
    /// on a broken caller is the worst available answer, and it is why
    /// these predicates read lines rather than the typed document: the
    /// precedence *proof* needs parseability and fails closed without it,
    /// which is the opposite obligation.
    @Test
    func anUnparseableWorkflowStillProducesDiagnostics() throws {
        let broken = """
            jobs:
              build:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
                 bad-indent: [unclosed
            """
        let findings = try Self.findings("swift-standards/swift-x", ci: broken)
        #expect(findings.count == 3)
    }

    // MARK: - Scope

    /// `[GH-REPO-074]` scopes to per-package repositories. No root
    /// manifest, no obligation — an inline workflow in a non-package
    /// repository is not a thin-caller violation.
    @Test
    func aRepositoryWithoutARootManifestIsOutOfScope() throws {
        let (subject, root) = try Self.subject(
            "swift-standards/swift-x", ci: "jobs:\n  a:\n    runs-on: ubuntu-latest\n")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appending(path: "Package.swift"))
        #expect(try CI.Validation.ThinCallers().findings(in: subject).isEmpty)
    }

    /// The consolidated legs must not come back as standalone files, and
    /// this fires independently of `ci.yml` — including when `ci.yml` is
    /// perfectly conforming.
    @Test
    func standaloneFormatAndLintWorkflowsFireOnTheirOwn() throws {
        let findings = try Self.findings(
            "swift-standards/swift-x", ci: Self.inheritCaller,
            files: [
                ".github/workflows/swift-format.yml": "name: fmt\n",
                ".github/workflows/swiftlint.yml": "name: lint\n",
            ])
        #expect(findings.count == 2)
        #expect(findings.allSatisfy { $0.message.contains("exists as a standalone file") })
    }

    // MARK: - INTEGRATED-DOCS-ADMISSION

    /// TX10 deleted the input, so any value is a live undeclared-input
    /// breakage; absence is the terminal shape and is not a finding. The
    /// rule reads the `ci` job only.
    @Test
    func theDeletedBridgeInputFiresOnAnyValueAndOnlyOnTheCiJob() throws {
        let caller = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                with:
                  integrated-docs: true
                secrets: inherit
            """
        let findings = try Self.findings("swift-standards/swift-x", ci: caller)
            .filter { $0.rule.rawValue == "INTEGRATED-DOCS-ADMISSION" }
        #expect(findings.count == 1)
        #expect(findings[0].message.contains("integrated-docs: true"))
        #expect(try Self.findings("swift-standards/swift-x", ci: Self.inheritCaller).isEmpty)
    }

    // MARK: - Registration

    /// Every rule the retired script emitted has a Swift owner, and the
    /// registry resolves each to this validator. `CI-059-EXEMPT` is
    /// deliberately absent: it is a reporting spelling for a suppressed
    /// `CI-059`, not a rule anything is authoritative for.
    @Test
    func everyRuleResolvesToThisValidator() {
        for rule in ["CI-030", "CI-059", "GH-REPO-074", "INTEGRATED-DOCS-ADMISSION"] {
            let validator = CI.Validation.Registry.validator(for: .init(rule))
            #expect(validator is CI.Validation.ThinCallers, "\(rule)")
        }
        #expect(CI.Validation.Registry.validator(for: "CI-059-EXEMPT") == nil)
    }
}
