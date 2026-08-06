extension Repository.Policy.Caller {
    /// Deterministic host projections of one caller spec. Two forms:
    ///
    /// - `current` — byte parity with the incumbent generate-caller.py
    ///   TERMINAL form (wrapper call, tag trigger, legacy secrets); the
    ///   F3 fixture-corpus parity gate compares against the incumbent.
    /// - `direct` — the FT1-ratified no-tag leaf calling the universal
    ///   reusable directly with the two-name secret map; activates in
    ///   the F13/F14 caller wave.
    ///
    /// This renderer is a closed projection: it emits only admitted
    /// declarations (triggers/filters, root read ceiling, one
    /// concurrency declaration, one reusable call, typed inputs, exact
    /// secret map). A declaration it cannot represent is STOP-F3-YAML,
    /// never a hand-authored escape.
    public enum Render {
        public static func current(_ caller: Repository.Policy.Caller) -> String {
            var lines = [
                "name: CI",
                "",
                "on:",
                "  push:",
                "    branches:",
                "      - main",
                "    tags:",
                "      - '*'",
                "  pull_request:",
                "    branches:",
                "      - main",
                "  workflow_dispatch:",
                "",
                "permissions:",
                "  actions: read",
                "  contents: read",
                "",
                "concurrency:",
                "  group: ci-${{ github.ref }}",
                "  cancel-in-progress: true",
                "",
                "jobs:",
                "  ci:",
                "    uses: \(caller.layer.wrapperOrganization)/.github/.github/workflows/swift-ci.yml@main",
            ]
            lines += withLines(caller)
            if caller.sameOrganization {
                lines.append("    secrets: inherit")
            } else {
                lines.append("    secrets:")
                for name in Repository.Policy.Caller.legacySecretNames {
                    lines.append("      \(name): ${{ secrets.\(name) }}")
                }
            }
            return lines.joined(separator: "\n") + "\n"
        }

        /// - Parameter privateDependencyClosure: emit the two-name secret
        ///   map only when the repository's measured dependency closure
        ///   requires it (FT1 secret profile; §15).
        public static func direct(
            _ caller: Repository.Policy.Caller,
            privateDependencyClosure: Bool = false
        ) -> String {
            var lines = [
                "name: CI",
                "",
                "on:",
                "  push:",
                "    branches:",
                "      - main",
                "  pull_request:",
                "    branches:",
                "      - main",
                "  workflow_dispatch:",
                "",
                "permissions:",
                "  actions: read",
                "  contents: read",
                "",
                "concurrency:",
                "  group: ci-${{ github.ref }}",
                "  cancel-in-progress: true",
                "",
                "jobs:",
                "  ci:",
                // Visibility gate (principal decision, #358 comment
                // 5205099233). The terminal caller is UNIFORM across
                // every repository, public and private: a private
                // repository skips all work here rather than being
                // provisioned with per-repo secrets or variables, so the
                // `one secret, one variable` org end state holds. The
                // idiom is the one every control-plane workflow already
                // uses (e.g. notify-linter-republish.yml).
                //
                // On a PUBLIC repository the expression is constant-true,
                // so the job set and the whole `ci / matrix / <job>`
                // check-context family are unchanged — an `if` alters
                // neither job ids nor display names, and `ci-ok` lives
                // inside the callee, where it is unaffected. On a PRIVATE
                // repository the job (and with it every nested context)
                // is simply never created; there is no required-check
                // surface there to strand, since private repositories
                // cannot carry branch rulesets on the current plan
                // (R33) and converge through `verification / workspace`
                // instead.
                "    if: ${{ !github.event.repository.private }}",
                // The required check context is the measured incumbent
                // family `ci / matrix / <job>` (caller job `ci` → wrapper
                // job `matrix` → universal). The wrapper hop dies in the
                // direct form, so its display segment transfers here: the
                // job's display name carries both segments and GitHub
                // concatenates display names into nested check names.
                // Context migration is refused (R-08); K-11 measures this
                // on a hosted canary before any fleet activation.
                "    name: ci / matrix",
                "    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main",
            ]
            // lint-bundle is a LAYER property the wrapper used to own
            // (its literal per layer; a package cannot elect a weaker
            // bundle). The direct form transfers it here explicitly:
            // without this line, a package with no root Lint.swift would
            // silently fall to the universal's `institute` default (K-12
            // property transfer, Goal swift-institute/.github#358).
            lines.append("    with:")
            lines.append("      lint-bundle: \(caller.layer.lintBundle)")
            lines += orderedInputLines(caller)
            if privateDependencyClosure {
                lines.append("    secrets:")
                lines += terminalSecretLines
            }
            if Repository.Policy.Caller.linterRulePackRepositories.contains(caller.repository) {
                lines += notifyLinterRepublishJob
            }
            return lines.joined(separator: "\n") + "\n"
        }

        /// The ruled second job for the five rule-pack repositories
        /// (principal ruling 2026-08-06, #358 comment 5202969590): on a
        /// main push, dispatch the central linter-republish pipeline for
        /// instant [CI-116] freshness. Emits the terminal credential
        /// shape — the app id rides each org's
        /// `SWIFT_INSTITUTE_BOT_APP_ID` **variable**, resolved inside the
        /// callee, so the caller forwards only the private key.
        /// notify-linter-republish.yml itself moved to this profile in
        /// the same caller wave (F14), which is why the caller no longer
        /// has an id-shaped secret to forward even as a fallback.
        static let notifyLinterRepublishJob: [String] = [
            "",
            "  notify-linter-republish:",
            "    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' && !github.event.repository.private }}",
            "    uses: swift-institute/.github/.github/workflows/notify-linter-republish.yml@main",
            "    secrets:",
        ] + terminalSecretLines

        /// The forwarded-secret lines, derived from the frozen terminal
        /// profile rather than restated. An id-shaped name cannot appear
        /// here without appearing in `terminalSecretNames` first.
        static let terminalSecretLines: [String] =
            Repository.Policy.Caller.terminalSecretNames.map {
                "      \($0): ${{ secrets.\($0) }}"
            }

        static func withLines(_ caller: Repository.Policy.Caller) -> [String] {
            let ordered = orderedInputLines(caller)
            guard !ordered.isEmpty else { return [] }
            return ["    with:"] + ordered
        }

        static func orderedInputLines(_ caller: Repository.Policy.Caller) -> [String] {
            Repository.Policy.Caller.approvedTypedInputs.compactMap { key in
                caller.inputs.first { $0.key == key }.map { "      \(key): \($0.value)" }
            }
        }
    }
}
