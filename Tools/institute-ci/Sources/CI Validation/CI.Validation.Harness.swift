import CI_Contract
import Foundation

extension CI.Validation {
    /// Runs registered validators against the fixture corpus and reports
    /// whether each scenario met its expectation.
    ///
    /// The Swift owner of `.github/scripts/tests/run.sh`.
    ///
    /// Two things about the shell original are preserved deliberately:
    ///
    /// - **`fail/` fixtures are the load-bearing ones.** A validator that
    ///   silently stopped firing passes every `pass/` and `edge/`
    ///   scenario. Four gates in this repository were inert for exactly
    ///   that reason.
    /// - **A fixture directory with no owner is not a pass.** `run.sh`
    ///   failed the whole run on any unregistered rule directory. That
    ///   invariant is kept but *armed*: during the port most directories
    ///   are legitimately unowned, so they are counted and named rather
    ///   than ignored, and `Report.isComplete` is the end-state gate that
    ///   turns the residue back into a failure.
    ///
    /// Unlike `run.sh` this runs in-process — no subprocess, no `python3`
    /// on `PATH`, and a validator's thrown `EnvironmentDefect` reaches
    /// the caller as itself instead of as an exit code parsed back out of
    /// a shell.
    public struct Harness: Sendable {
        public let corpus: Corpus

        public init(corpus: Corpus) {
            self.corpus = corpus
        }

        /// Run every scenario whose rule directory matches `prefix`.
        public func run(matching prefix: String = "") throws(EnvironmentDefect) -> Report {
            var outcomes: [Outcome] = []
            var unowned: [String] = []

            for directory in try corpus.ruleDirectories(matching: prefix) {
                guard let rule = Registry.rule(forCorpusDirectory: directory),
                      let validator = Registry.validator(for: rule)
                else {
                    unowned.append(directory)
                    continue
                }
                for scenario in try corpus.scenarios(in: directory) {
                    let findings = try validator.findings(in: scenario.subject)
                        .filter { $0.rule == rule }
                    outcomes.append(
                        Outcome(rule: rule, scenario: scenario, findings: findings))
                }
            }
            return Report(outcomes: outcomes, unownedRuleDirectories: unowned)
        }
    }
}

extension CI.Validation.Harness {
    /// One scenario's result.
    public struct Outcome: Sendable, Equatable {
        public let rule: CI.Validation.Rule
        public let scenario: CI.Validation.Corpus.Scenario
        public let findings: [CI.Validation.Finding]

        public var isSatisfied: Bool {
            scenario.expectation.expectsFindings ? !findings.isEmpty : findings.isEmpty
        }

        public var summary: String {
            let verdict = isSatisfied ? "PASS" : "FAIL"
            return "\(verdict) \(rule) \(scenario.expectation.rawValue)/\(scenario.name)"
                + " (\(findings.count) finding(s))"
        }
    }

    /// The whole run.
    public struct Report: Sendable, Equatable {
        public let outcomes: [Outcome]

        /// Rule directories in the corpus with no registered Swift
        /// validator. Named, not counted only — the residue of the port
        /// is a list a reader can act on.
        public let unownedRuleDirectories: [String]

        public var satisfied: [Outcome] { outcomes.filter(\.isSatisfied) }
        public var unsatisfied: [Outcome] { outcomes.filter { !$0.isSatisfied } }

        /// Every scenario met its expectation.
        public var isSatisfied: Bool { unsatisfied.isEmpty }

        /// Every scenario met its expectation **and** every rule
        /// directory has a Swift owner. This is the end-state gate: it
        /// becomes the CI condition when the port completes.
        public var isComplete: Bool { isSatisfied && unownedRuleDirectories.isEmpty }
    }
}
