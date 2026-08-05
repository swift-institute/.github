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
                "    uses: swift-institute/.github/.github/workflows/swift-ci.yml@main",
            ]
            lines += withLines(caller)
            if privateDependencyClosure {
                lines.append("    secrets:")
                lines.append("      SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY: ${{ secrets.SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY }}")
            }
            return lines.joined(separator: "\n") + "\n"
        }

        static func withLines(_ caller: Repository.Policy.Caller) -> [String] {
            let ordered = Repository.Policy.Caller.approvedTypedInputs.compactMap { key in
                caller.inputs.first { $0.key == key }.map { "      \(key): \($0.value)" }
            }
            guard !ordered.isEmpty else { return [] }
            return ["    with:"] + ordered
        }
    }
}
