import Testing

@testable import Fleet_Audit

/// The C8 sweep contract, proved without a credential.
///
/// Every case here is fed a recorded audit document or a recorded
/// yamllint transcript — the same inputs the retired `cron-audit-runner`
/// and `audit-mechanical-hygiene` were measured against for the port's
/// single comparison. Nothing in this suite lists an org, mints a token
/// or clones a repository, and nothing in this target can.
@Suite
struct FleetAuditTests {
    @Suite
    struct ConfigurationTests {
        /// The live `lint-mechanical-hygiene-weekly` caller's document.
        static let live = """
            {
              "json_totals_path": "totals",
              "count_keys": ["yaml_issues", "broken_links"],
              "extra_template": "- `{pkg}`: yaml={yaml_issues}, symlinks={broken_links}",
              "summary_label": "mechanical hygiene sweep (γ-2 consolidated)"
            }
            """

        @Test func `the live caller document decodes member for member`() throws {
            let configuration = try Fleet.Audit.Configuration(json: Self.live)
            #expect(configuration.totalsPath == "totals")
            #expect(configuration.countKeys == ["yaml_issues", "broken_links"])
            #expect(configuration.summaryLabel == "mechanical hygiene sweep (γ-2 consolidated)")
        }

        @Test func `absent extra when keys default to every count key`() throws {
            let configuration = try Fleet.Audit.Configuration(json: Self.live)
            #expect(configuration.extraWhenKeys == configuration.countKeys)
        }

        @Test func `an explicit extra when keys narrows the gate`() throws {
            let configuration = try Fleet.Audit.Configuration(
                json: #"{"count_keys":["a","b"],"extra_when_keys":["a"]}"#)
            #expect(configuration.extraWhenKeys == ["a"])
        }

        @Test func `an empty document takes the retired runner's defaults`() throws {
            let configuration = try Fleet.Audit.Configuration(json: "{}")
            #expect(configuration.totalsPath == "totals")
            #expect(configuration.countKeys.isEmpty)
            #expect(configuration.summaryLabel == "audit")
        }

        @Test func `a member of the wrong type refuses`() {
            #expect(throws: Fleet.Audit.Configuration.Error.wrongType(member: "count_keys")) {
                try Fleet.Audit.Configuration(json: #"{"count_keys":"yaml_issues"}"#)
            }
        }

        @Test func `a non object document refuses`() {
            #expect(throws: Fleet.Audit.Configuration.Error.notAnObject) {
                try Fleet.Audit.Configuration(json: "[]")
            }
            #expect(throws: Fleet.Audit.Configuration.Error.malformedJSON) {
                try Fleet.Audit.Configuration(json: "{")
            }
        }
    }

    @Suite
    struct ReportTests {
        static let document = """
            {
              "package": "swift-byte-primitives",
              "dir": "/tmp/clone",
              "totals": { "yaml_issues": 3, "broken_links": 0 }
            }
            """

        @Test func `counters read at the configured dotted path`() {
            let counters = Fleet.Audit.Report.counters(
                inJSON: Self.document, at: "totals",
                keys: ["yaml_issues", "broken_links"])
            #expect(counters == ["yaml_issues": 3, "broken_links": 0])
        }

        @Test func `an empty path reads the document root`() {
            let counters = Fleet.Audit.Report.counters(
                inJSON: #"{"missing": 4}"#, at: "", keys: ["missing"])
            #expect(counters == ["missing": 4])
        }

        @Test func `a nested path navigates`() {
            let counters = Fleet.Audit.Report.counters(
                inJSON: #"{"a":{"b":{"n":7}}}"#, at: "a.b", keys: ["n"])
            #expect(counters == ["n": 7])
        }

        @Test func `a path through a non object reads zero, not a crash`() {
            let counters = Fleet.Audit.Report.counters(
                inJSON: #"{"a": 1}"#, at: "a.b", keys: ["n"])
            #expect(counters == ["n": 0])
        }

        @Test func `an audit that could not run reads as zeros`() {
            // The retired runner swallowed OSError and JSONDecodeError
            // identically. A package whose audit crashed must not stop
            // the sweep over the rest of the org.
            #expect(
                Fleet.Audit.Report.counters(inJSON: "", at: "totals", keys: ["n"])
                    == ["n": 0])
            #expect(
                Fleet.Audit.Report.counters(inJSON: "not json", at: "totals", keys: ["n"])
                    == ["n": 0])
        }

        @Test func `a counter spelled as a string still counts`() {
            #expect(
                Fleet.Audit.Report.counters(
                    inJSON: #"{"totals":{"n":"12"}}"#, at: "totals", keys: ["n"])
                    == ["n": 12])
        }

        @Test func `a null counter reads zero`() {
            #expect(
                Fleet.Audit.Report.counters(
                    inJSON: #"{"totals":{"n":null}}"#, at: "totals", keys: ["n"])
                    == ["n": 0])
        }
    }

    @Suite
    struct SweepTests {
        static func sweep(
            countKeys: [String] = ["yaml_issues", "broken_links"],
            template: String = "- `{pkg}`: yaml={yaml_issues}, symlinks={broken_links}",
            whenKeys: [String]? = nil
        ) -> Fleet.Audit.Sweep {
            Fleet.Audit.Sweep(
                organization: "swift-primitives",
                configuration: .init(
                    countKeys: countKeys, extraTemplate: template,
                    extraWhenKeys: whenKeys,
                    summaryLabel: "mechanical hygiene sweep (γ-2 consolidated)"))
        }

        static func report(
            _ package: String, _ yaml: Int, _ links: Int
        ) -> (package: String, report: Fleet.Audit.Report) {
            (package, Fleet.Audit.MechanicalHygiene.report(
                package: package, yamlIssues: yaml, brokenLinks: links))
        }

        @Test func `totals accumulate across packages`() throws {
            let outcome = try Self.sweep().accumulate([
                Self.report("swift-a", 3, 0),
                Self.report("swift-b", 1, 2),
            ])
            #expect(outcome.totals == ["yaml_issues": 4, "broken_links": 2])
        }

        @Test func `the counts artefact is positional and newline terminated`() throws {
            let outcome = try Self.sweep().accumulate([Self.report("swift-a", 3, 1)])
            #expect(
                outcome.countsArtefact(keys: ["yaml_issues", "broken_links"]) == "3,1\n")
            // Order is the caller's `count-labels` order; reversing the
            // keys must reverse the artefact, or the labels lie.
            #expect(
                outcome.countsArtefact(keys: ["broken_links", "yaml_issues"]) == "1,3\n")
        }

        @Test func `a clean sweep still reports zeros`() throws {
            let outcome = try Self.sweep().accumulate([Self.report("swift-a", 0, 0)])
            #expect(outcome.countsArtefact(keys: ["yaml_issues", "broken_links"]) == "0,0\n")
            #expect(outcome.extraArtefact == nil)
        }

        @Test func `only packages with a positive counter get a line`() throws {
            let outcome = try Self.sweep().accumulate([
                Self.report("swift-a", 0, 0),
                Self.report("swift-b", 2, 0),
            ])
            #expect(outcome.perPackage == ["- `swift-b`: yaml=2, symlinks=0"])
            #expect(outcome.extraArtefact == "- `swift-b`: yaml=2, symlinks=0\n")
        }

        @Test func `the gate narrows to the named counters`() throws {
            let outcome = try Self.sweep(whenKeys: ["yaml_issues"]).accumulate([
                Self.report("swift-a", 0, 5)
            ])
            #expect(outcome.perPackage.isEmpty)
        }

        @Test func `an empty template disables the per package artefact`() throws {
            let outcome = try Self.sweep(template: "").accumulate([Self.report("swift-a", 9, 9)])
            #expect(outcome.extraArtefact == nil)
            #expect(outcome.totals == ["yaml_issues": 9, "broken_links": 9])
        }

        @Test func `the summary heading names the org and the label`() throws {
            let outcome = try Self.sweep().accumulate([Self.report("swift-a", 3, 1)])
            #expect(
                outcome.summary(
                    organization: "swift-primitives",
                    label: "mechanical hygiene sweep (γ-2 consolidated)",
                    keys: ["yaml_issues", "broken_links"])
                    == """
                    ## Org swift-primitives — mechanical hygiene sweep (γ-2 consolidated)
                    - yaml_issues: 3
                    - broken_links: 1

                    """)
        }

        @Test func `a template placeholder with no counter is named, not guessed`() {
            #expect(throws: Fleet.Audit.Sweep.Error.unknownPlaceholder("licenses")) {
                try Self.sweep(template: "{pkg}: {licenses}").accumulate([
                    Self.report("swift-a", 1, 0)
                ])
            }
        }

        @Test func `a doubled brace is a literal brace`() throws {
            #expect(
                try Fleet.Audit.Sweep.render(
                    "{{{pkg}}}", package: "swift-a", counters: [:]) == "{swift-a}")
        }

        @Test func `an unbalanced template refuses`() {
            #expect(throws: Fleet.Audit.Sweep.Error.malformedTemplate("{pkg")) {
                try Fleet.Audit.Sweep.render("{pkg", package: "a", counters: [:])
            }
        }
    }

    @Suite
    struct MechanicalHygieneTests {
        /// A recorded yamllint transcript: two file headings, three
        /// diagnostics, one continuation line.
        static let transcript = """
            /tmp/clone/.github/workflows/ci.yml
              14:81     warning  line too long (203 > 200 characters)  (line-length)
              22:1      error    wrong indentation: expected 2 but found 4  (indentation)

            /tmp/clone/metadata.yaml
              3:1       error    missing document start  (document-start)

            """

        @Test func `each indented line column diagnostic counts once`() {
            #expect(
                Fleet.Audit.MechanicalHygiene.yamlIssueCount(inTranscript: Self.transcript) == 3)
        }

        @Test func `file headings are not diagnostics`() {
            #expect(
                Fleet.Audit.MechanicalHygiene.yamlIssueCount(
                    inTranscript: "/tmp/clone/.github/workflows/ci.yml\n") == 0)
        }

        @Test func `an empty transcript counts nothing`() {
            #expect(Fleet.Audit.MechanicalHygiene.yamlIssueCount(inTranscript: "") == 0)
        }

        @Test func `a line whose head is not line colon column is not counted`() {
            // Widening this shape would move every package's baseline at
            // once, so the negative controls are as load-bearing as the
            // positive one.
            for line in ["  note: something", "  12:34:56 error", "  :1 error", "  1: error"] {
                #expect(
                    Fleet.Audit.MechanicalHygiene.yamlIssueCount(inTranscript: line) == 0,
                    "counted \(line)")
            }
        }

        @Test func `the scan scope is the four Research subjects, in order`() {
            #expect(
                Fleet.Audit.MechanicalHygiene.subjects.map(\.path) == [
                    ".github/workflows", ".github/dependabot.yml",
                    ".github/metadata.yaml", "metadata.yaml",
                ])
            // [CI-057] leaves these to the package.
            #expect(
                !Fleet.Audit.MechanicalHygiene.subjects.contains {
                    $0.path.contains("swiftlint") || $0.path.contains("swift-format")
                })
        }

        @Test func `only subjects of the right kind, present in the clone, are linted`() {
            let present = Fleet.Audit.MechanicalHygiene.present(in: "/c") { path, isDirectory in
                (path == "/c/.github/workflows" && isDirectory)
                    || (path == "/c/metadata.yaml" && !isDirectory)
            }
            #expect(present == ["/c/.github/workflows", "/c/metadata.yaml"])
        }

        @Test func `a file where a directory was expected is not a subject`() {
            let present = Fleet.Audit.MechanicalHygiene.present(in: "/c") { path, isDirectory in
                path == "/c/.github/workflows" && !isDirectory
            }
            #expect(present.isEmpty)
        }

        @Test func `only dangling symlinks are broken links`() {
            #expect(
                Fleet.Audit.MechanicalHygiene.brokenLinkCount(among: [
                    ("/c/a", true, false),
                    ("/c/b", true, true),
                    ("/c/d", false, false),
                ]) == 1)
        }
    }

    @Suite
    struct YamllintTests {
        @Test func `the rule set keeps the numbers the baseline was taken at`() {
            let configuration = Fleet.Audit.Yamllint.configuration
            #expect(configuration.contains("max: 200"))
            #expect(configuration.contains("spaces: 2"))
            #expect(configuration.contains("document-start: disable"))
            #expect(configuration.contains(#"allowed-values: ["true", "false"]"#))
            #expect(configuration.contains("require-starting-space: false"))
        }

        @Test func `the audit reads the config the setup writes`() {
            #expect(
                Fleet.Audit.Yamllint.invocation(subjects: ["/c/metadata.yaml"])
                    == ["yamllint", "-c", Fleet.Audit.Yamllint.configurationPath,
                        "/c/metadata.yaml"])
        }
    }
}
