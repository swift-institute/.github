import CI_Contract
import CI_Workflow
import Foundation
import Testing

@testable import CI_Validation

/// `[CI-MANIFEST-BINDING]`.
///
/// The fixture corpus under `tests/fixtures/ci-manifest-binding/` is
/// exercised by the harness suite, which runs every registered validator
/// over every scenario. What is here is what the corpus cannot express:
/// the assertion against this repository's own live manifest, and the
/// two reading decisions that would each turn the rule silently inert.
@Suite
struct CIValidationManifestBindingTests {
    /// This repository, located from the file rather than the working
    /// directory.
    static var repository: CI.Validation.Subject {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return .init(repository: "swift-institute/.github", root: url.path)
    }

    @Suite
    struct Integration {
        /// The fail-closed gate. If a validator is added without a
        /// manifest entry, or a deprecated entry keeps a stale script, or
        /// a self-firing entry stops resolving to a triggering workflow,
        /// this is what turns red.
        @Test func `this repository's own manifest is internally consistent`() throws {
            let findings = try CI.Validation.ManifestBinding()
                .findings(in: CIValidationManifestBindingTests.repository)
            // One known finding is carried by the repository at the time
            // of the port and is the retired script's finding too,
            // byte-for-byte; the assertion is that the set does not grow.
            #expect(findings.count <= 1)
        }

        /// A count from the wrong root is not evidence. If the manifest
        /// ever reads as empty, "no findings" above would be vacuous.
        @Test func `the live manifest is non-empty`() throws {
            let text = try #require(
                try CIValidationManifestBindingTests.repository.text(
                    at: CI.Validation.ManifestBinding.manifestPath))
            #expect(text.contains("validators:"))
            #expect(text.components(separatedBy: "rule-id:").count > 40)
        }

        /// The permanent exception, asserted rather than only documented.
        ///
        /// Check 2 scans for `validate-*.py`. The fixture stubs are the
        /// only reason `fail/missing-reference` can fail, so a sweep that
        /// "finished the Swift port" by deleting them would leave this
        /// rule passing on a corpus that no longer tests it.
        ///
        /// There are **two** stub families, and the guard must hold both:
        ///
        /// - `tests/fixtures/ci-manifest-binding/` — the eight stubs this
        ///   rule's own corpus is built from.
        /// - `tests/schema-correspondence/` — five `validate-readme.py`
        ///   copies. They are the corpus for GH-REPO-063's re-specified
        ///   check and stay whatever becomes of the production
        ///   `validate-readme.py`; if that validator is ported, these
        ///   remain as the fixture set for the Swift re-specification.
        ///   Check 2 counts them as `validate-*.py` on disk either way.
        ///
        /// Membership is pinned **exactly**, per family. The floor this
        /// replaced (`>= 4`) could not do the job the paragraph above
        /// describes: a sweep deleting four of the eight, or all five of
        /// the schema-correspondence copies, still satisfied it. A test
        /// whose purpose is to fail when the corpus shrinks must count.
        @Test func `the fixture stubs are still Python and still present`() throws {
            var url = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { url.deleteLastPathComponent() }

            func stubs(under path: String) -> [String] {
                let root = url.appendingPathComponent(path)
                return (FileManager.default
                    .enumerator(atPath: root.path)?
                    .compactMap { $0 as? String }
                    .filter { $0.hasSuffix(".py") } ?? [])
                    .sorted()
            }

            #expect(
                stubs(under: ".github/scripts/tests/fixtures/ci-manifest-binding") == [
                    "edge/multi-rule-same-script/.github/scripts/validate-paired.py",
                    "edge/self-firing-deferred-no-triggers/.github/scripts/validate-stub.py",
                    "fail/deprecated-non-empty/.github/scripts/validate-foo.py",
                    "fail/missing-reference/.github/scripts/validate-bar.py",
                    "fail/missing-reference/.github/scripts/validate-foo.py",
                    "fail/self-firing-active-missing-triggers/.github/scripts/validate-stub.py",
                    "pass/clean/.github/scripts/validate-foo.py",
                    "pass/self-firing-active-with-triggers/.github/scripts/validate-stub.py",
                ])

            #expect(
                stubs(under: ".github/scripts/tests/schema-correspondence") == [
                    "fail/constant-renamed/validate-readme.py",
                    "fail/readme-exempt-unhandled/validate-readme.py",
                    "fail/readme-family-unhandled/validate-readme.py",
                    "fail/settings-key-unread/validate-readme.py",
                    "pass/consistent/validate-readme.py",
                ])
        }
    }

    @Suite
    struct Unit {
        /// The YAML 1.1 recovery. A bare `on:` resolves to the boolean
        /// `true`, so a reader that only asked for the string key would
        /// find no triggers on any workflow and report every self-firing
        /// entry as broken.
        @Test func `a bare on key is reached through its boolean spelling`() throws {
            let document = try CI.Workflow.YAML.Parser.parse(
                """
                name: x
                on:
                  push:
                    branches: [main]
                  pull_request: {}
                """)
            let mapping = try #require(document.mapping)
            #expect(mapping["on"] == nil)
            #expect(
                CI.Validation.ManifestBinding.triggerKeys(of: mapping) == ["push", "pull_request"])
        }

        @Test func `a quoted on key is a different key and still reads`() throws {
            let document = try CI.Workflow.YAML.Parser.parse(
                """
                "on":
                  push: {}
                """)
            let mapping = try #require(document.mapping)
            #expect(CI.Validation.ManifestBinding.triggerKeys(of: mapping) == ["push"])
        }

        @Test func `the sequence and scalar forms of on are read too`() throws {
            let sequence = try #require(
                try CI.Workflow.YAML.Parser.parse("on: [push, pull_request]").mapping)
            #expect(
                CI.Validation.ManifestBinding.triggerKeys(of: sequence) == ["push", "pull_request"])
            let scalar = try #require(try CI.Workflow.YAML.Parser.parse("on: push").mapping)
            #expect(CI.Validation.ManifestBinding.triggerKeys(of: scalar) == ["push"])
        }

        /// Message text inherited from the retired corpus, and load-bearing
        /// while its counterpart still exists.
        @Test func `retired renderings match Python's repr`() {
            #expect(CI.Validation.Retired.quoted("CI-010") == "'CI-010'")
            #expect(CI.Validation.Retired.list(["push", "pull_request"]) == "['push', 'pull_request']")
            #expect(CI.Validation.Retired.value(.null) == "None")
            #expect(CI.Validation.Retired.value(.boolean(true)) == "True")
            #expect(CI.Validation.Retired.typeName(.sequence([])) == "list")
            #expect(!CI.Validation.Retired.isTruthy(.text("")))
            #expect(CI.Validation.Retired.isTruthy(.text("x")))
        }
    }

    @Suite
    struct `Edge Case` {
        /// Absence of the manifest is a *finding*, not a defect: the
        /// question "does this repository bind its validators?" was asked
        /// and answered.
        @Test func `a missing manifest is a finding and not an exit-2`() throws {
            let subject = CI.Validation.Subject(
                repository: "swift-institute-test/empty", root: NSTemporaryDirectory())
            let findings = try CI.Validation.ManifestBinding().findings(in: subject)
            #expect(findings.count == 1)
            #expect(findings[0].message.hasPrefix("manifest missing:"))
        }
    }
}
