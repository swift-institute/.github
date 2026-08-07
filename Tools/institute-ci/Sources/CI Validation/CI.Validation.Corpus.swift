import CI_Contract
import Foundation

extension CI.Validation {
    /// The fixture corpus: `<root>/<rule-id>/{pass,fail,edge}/<scenario>/`.
    ///
    /// 515 files across 68 rule directories, and they are **data**. They
    /// are not regenerated, tidied, or edited alongside the validator
    /// they exercise — a fixture changed in the same commit as its
    /// predicate proves nothing. This type only reads them.
    ///
    /// The directory name is the rule identifier, lower-cased. That is
    /// the whole binding; `tests/run.sh` needed a hand-maintained
    /// `prefix_for` table for it, which is exactly the kind of second
    /// spelling that drifts.
    public struct Corpus: Sendable {
        /// What a scenario directory asserts.
        public enum Expectation: String, Sendable, CaseIterable {
            /// `pass/` — the shape is correct; zero findings.
            case clean = "pass"
            /// `fail/` — the shape is defective; at least one finding.
            case violating = "fail"
            /// `edge/` — the shape is exempt; zero findings.
            ///
            /// Distinct from `pass` even though the assertion matches,
            /// because an exemption that silently became a plain pass is
            /// a rule that stopped covering its hardest case.
            case exempt = "edge"

            var expectsFindings: Bool { self == .violating }
        }

        /// One scenario directory.
        public struct Scenario: Sendable, Equatable {
            /// The rule directory this scenario sits under — the rule
            /// identifier, lower-cased. Resolved to a `Rule` by
            /// `Registry.rule(forCorpusDirectory:)`, which is where the
            /// registered spelling lives.
            public let directory: String
            public let expectation: Expectation
            public let name: String
            public let root: String

            /// The reporting name the retired harness used. Preserved
            /// byte-for-byte: it appears in the TSV the differential gate
            /// compares.
            public var repository: String { "swift-institute-test/\(name)" }

            public var subject: Subject {
                Subject(repository: repository, root: root)
            }
        }

        public let root: String

        public init(root: String) {
            self.root = root
        }

        /// Every rule directory, sorted, optionally restricted to a
        /// prefix. A non-matching directory is not a skip — it was never
        /// selected.
        public func ruleDirectories(matching prefix: String = "") throws(EnvironmentDefect) -> [String] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                throw EnvironmentDefect.unreadableSubject(root: root)
            }
            return names
                .filter { $0.hasPrefix(prefix) }
                .filter { isDirectory("\(root)/\($0)") }
                .sorted()
        }

        /// Every scenario under one rule directory, in
        /// expectation-then-name order.
        public func scenarios(in directory: String) throws(EnvironmentDefect) -> [Scenario] {
            var scenarios: [Scenario] = []
            for expectation in Expectation.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                let path = "\(root)/\(directory)/\(expectation.rawValue)"
                guard isDirectory(path) else { continue }
                let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                for name in names.sorted() where isDirectory("\(path)/\(name)") {
                    scenarios.append(
                        Scenario(
                            directory: directory, expectation: expectation, name: name,
                            root: "\(path)/\(name)"))
                }
            }
            return scenarios
        }

        private func isDirectory(_ path: String) -> Bool {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }
}
