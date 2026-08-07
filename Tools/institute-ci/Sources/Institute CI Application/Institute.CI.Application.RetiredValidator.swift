import CI_Contract
import CI_Validation
import Foundation
import Institute_Receipt

/// The transitional bridge that keeps the fixture corpus fully gated
/// while the port is only partly done.
///
/// `.github/scripts/tests/run.sh` used to run the whole corpus, and
/// it cannot survive a single Python deletion: leave a deleted
/// script's dispatch arm and it invokes a path that no longer exists;
/// remove the arm and the rule directory becomes an unregistered
/// rule, which `run.sh` prints as `SKIP` and exits `1` on, by design.
/// There is no per-class edit that keeps it green, so it is retired
/// here in favour of `CI.Validation.Harness` — its Swift owner since
/// C0.
///
/// Retiring it moves one problem: the harness only runs *registered*
/// validators, so during the port the rule directories nobody has
/// ported yet would stop being exercised at all. A gate that silently
/// narrows as the port proceeds is worse than the one it replaced.
/// So the `validate-fixtures` face runs the harness for every ported
/// rule and the retired script for every rule that is not — the same
/// registry-driven dispatch `validate-base.yml` performs over live
/// repositories, applied to the corpus.
///
/// **This table is scaffolding and it shrinks to nothing.** Every
/// entry is deleted by the class that ports its rule, in the same
/// pull request as the script; when the last one goes, so does this
/// file. Nothing else may consult it, and nothing may be added to it.
extension Institute.CI.Application {
    public enum RetiredValidator {
        /// Fixture rule directory → retired script, relative to
        /// `.github/scripts/`. Transcribed from `run.sh`'s `validator_for`
        /// at its final revision; the rules ported through C2 are already
        /// absent because their validators answer from the registry.
        public static let scripts: [String: String] = [
            "api-impl-006": "validate-file-naming.py",
            "api-impl-007": "validate-file-naming.py",
            "api-name-009": "validate-diagnostic-format.py",
            "arch-layer-012": "validate-test-target-layers.py",
            "ci-004b": "validate-sub-org-wrappers.py",
            "ci-030": "validate-thin-callers.py",
            "ci-040": "validate-cache-policy.py",
            "ci-042": "validate-cache-policy.py",
            "ci-058": "validate-input-defaults.py",
            "ci-059": "validate-thin-callers.py",
            "ci-080": "validate-harden-runner.py",
            "ci-090": "validate-permissions-shape.py",
            "ci-097": "validate-permissions-shape.py",
            "ci-100": "validate-swiftlint-rules.py",
            "doc-020": "validate-docc-structure.py",
            "gh-repo-074": "validate-thin-callers.py",
            "mod-023": "validate-package-naming.py",
            "mod-032": "validate-package-graph.py",
            "mod-038": "validate-target-imports.py",
            "pattern-001": "validate-package-shape.py",
            "pattern-003": "validate-package-shape.py",
            "pattern-004": "validate-package-shape.py",
            "pattern-004b": "validate-package-shape.py",
            "pattern-004c": "validate-package-shape.py",
            "pattern-005": "validate-package-shape.py",
            "pattern-006": "validate-package-shape.py",
            "pattern-022": "validate-package-shape.py",
            "pkg-dep-008": "validate-package-identity.py",
            "pkg-name-014": "validate-package-naming.py",
            "pkg-name-017": "validate-package-naming.py",
            "plat-arch-004": "validate-platform-architecture.py",
            "plat-arch-005": "validate-platform-architecture.py",
            "plat-arch-006": "validate-platform-architecture.py",
            "plat-arch-007": "validate-platform-architecture.py",
            "plat-arch-008": "validate-layer-deps.py",
            "plat-arch-008c": "validate-platform-architecture.py",
            "plat-arch-008h": "validate-layer-deps.py",
            "plat-arch-008j": "validate-platform-architecture.py",
            "plat-arch-027": "validate-platform-architecture.py",
            "prim-name-001": "validate-package-naming.py",
            "swiftlint-bitpattern-comment": "validate-swiftlint-bitpattern-comment.py",
            "swiftlint-witness-exemption": "validate-swiftlint-witness-exemption.py",
            "test-009": "validate-file-naming.py",
        ]

        /// The rule identifier a retired script cites in column 2 for a
        /// given fixture directory.
        ///
        /// `run.sh` kept this as a second `case` statement that could,
        /// and did, disagree with the first. It is derived here instead:
        /// upper-cased directory name, except where the retired corpus
        /// spells the identifier differently. Those exceptions are the
        /// whole reason the second table existed, so they are the only
        /// thing written down.
        public static let ruleSpellings: [String: String] = [
            "mod-023": "PKG-NAME-EXTERNAL-MACRO",
            "mod-032": "PACKAGE-CYCLE",
            "mod-038": "TARGET-IMPORT-EDGE",
            "plat-arch-008c": "PLAT-ARCH-008c",
            "plat-arch-008h": "PLAT-ARCH-008h",
            "plat-arch-008j": "PLAT-ARCH-008j",
            "pattern-004b": "PATTERN-004b",
            "pattern-004c": "PATTERN-004c",
            "ci-004b": "CI-004b",
        ]

        public static func rule(forDirectory directory: String) -> String {
            if let spelling = ruleSpellings[directory] { return spelling }
            // Skill-hygiene findings are named for the behaviour rather
            // than an internal rule ID, so the directory and the emitted
            // code are the same string.
            if directory.hasPrefix("skill-") { return directory }
            return directory.uppercased()
        }
    }
}

extension Institute.CI.Application.RetiredValidator {
    /// Run one retired script over one fixture repository and return its
    /// stdout.
    ///
    /// Process spawning belongs to the Application layer, not to
    /// `CI Validation`: a validator is a pure question by contract, and
    /// the predicate library must not gain the ability to run arbitrary
    /// programs just because the transition needs it for a few weeks.
    ///
    /// Failure is deliberately quiet. A retired script that crashes
    /// produces no findings, which the caller reads as an unmet
    /// expectation on its `fail/` fixtures — the same signal `run.sh`
    /// gave, arrived at without a second error channel.
    public static func run(script: String, repository: String, root: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script, repository, root]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
