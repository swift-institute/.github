import CI_Contract
import Foundation
import Testing

@testable import CI_Validation

/// The Swift replacement for running `.github/scripts/tests/run.sh`.
///
/// Every registered validator runs against the real fixture corpus — the
/// same files, unmodified — and each scenario must meet the expectation
/// its directory declares.
@Suite
struct CIValidationHarnessTests {
    /// The corpus, located from this file rather than from a working
    /// directory, so the suite behaves the same under SwiftPM, Xcode, and
    /// CI.
    static var corpus: CI.Validation.Corpus {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }  // → repository root
        return .init(root: url.appendingPathComponent(".github/scripts/tests/fixtures").path)
    }

    @Suite
    struct Unit {
        @Test func `expectations map to their directory names`() {
            #expect(CI.Validation.Corpus.Expectation(rawValue: "pass") == .clean)
            #expect(CI.Validation.Corpus.Expectation(rawValue: "fail") == .violating)
            #expect(CI.Validation.Corpus.Expectation(rawValue: "edge") == .exempt)
        }

        @Test func `only violating scenarios expect findings`() {
            #expect(CI.Validation.Corpus.Expectation.violating.expectsFindings)
            #expect(!CI.Validation.Corpus.Expectation.clean.expectsFindings)
            #expect(!CI.Validation.Corpus.Expectation.exempt.expectsFindings)
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `a missing corpus is an environment defect not an empty pass`() {
            #expect(throws: CI.Validation.EnvironmentDefect.self) {
                _ = try CI.Validation.Corpus(root: "/nonexistent-corpus").ruleDirectories()
            }
        }

        @Test func `port residue is named not silently skipped`() throws {
            // `run.sh` failed the whole run on an unregistered rule
            // directory. During the port that residue is expected, so the
            // invariant becomes: every directory is either owned or
            // listed — none may vanish from the accounting.
            let corpus = CIValidationHarnessTests.corpus
            let directories = try corpus.ruleDirectories()
            let report = try CI.Validation.Harness(corpus: corpus).run()
            let owned = Set(
                directories.filter {
                    CI.Validation.Registry.rule(forCorpusDirectory: $0) != nil
                })
            let listed = Set(report.unownedRuleDirectories)
            #expect(owned.isDisjoint(with: listed))
            #expect(owned.count + listed.count == directories.count)
        }
    }

    @Suite
    struct Integration {
        @Test func `the fixture corpus is where the harness expects it`() throws {
            let directories = try CIValidationHarnessTests.corpus.ruleDirectories()
            #expect(
                directories.count > 60,
                "expected the 68-directory corpus, found \(directories.count)")
        }

        @Test func `every scenario meets its expectation`() throws {
            let report = try CI.Validation.Harness(corpus: CIValidationHarnessTests.corpus).run()
            for outcome in report.unsatisfied { Issue.record("\(outcome.summary)") }
            #expect(report.isSatisfied)
            // Guard against a silently empty run: a harness that checks
            // nothing passes everything, which is how four gates in this
            // repository sat inert.
            #expect(!report.outcomes.isEmpty)
        }

        @Test func `violating scenarios actually fire`() throws {
            // The assertion that catches a validator that stopped firing.
            let report = try CI.Validation.Harness(corpus: CIValidationHarnessTests.corpus).run()
            let violating = report.outcomes.filter { $0.scenario.expectation == .violating }
            #expect(!violating.isEmpty)
            for outcome in violating {
                #expect(!outcome.findings.isEmpty, "\(outcome.rule) \(outcome.scenario.name)")
            }
        }
    }
}
