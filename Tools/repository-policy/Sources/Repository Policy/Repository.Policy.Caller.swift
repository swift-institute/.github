extension Repository.Policy {
    /// One package repository's typed caller spec — the routing row the
    /// restricted renderer projects into `.github/workflows/ci.yml`
    /// (F3; swift-institute/.github#366; FT1-ratification.json).
    public struct Caller: Sendable, Equatable {
        public enum Layer: String, Sendable, Equatable, CaseIterable {
            case primitives
            case standards
            case institute

            /// The layer's canonical wrapper organization (current
            /// topology). The org is compared against this, never used
            /// to infer the layer.
            public var wrapperOrganization: String {
                switch self {
                case .primitives: "swift-primitives"
                case .standards: "swift-standards"
                case .institute: "swift-foundations"
                }
            }

            /// The layer's lint bundle — the literal the layer wrapper
            /// used to own, transferred into the direct leaf by the
            /// renderer (K-12 property transfer). Same tokens as the
            /// universal's `lint-bundle` input and Workspace's
            /// `Workspace.Lint.Bundle`.
            public var lintBundle: String {
                switch self {
                case .primitives: "primitives"
                case .standards: "standards"
                case .institute: "institute"
                }
            }
        }

        public enum Error: Swift.Error, Equatable {
            case malformedRepository(String)

            /// A rendered caller carries something `Parse` does not model
            /// — an unapproved `with:` key, an inline `runs-on:`/`steps:`,
            /// an extra job, a cross-wrapper docs route. The associated
            /// value names exactly what did not fit.
            ///
            /// The caller carrying it is not a defect. It is a typed
            /// exception for review, which is why `Parse` refuses rather
            /// than regenerating over it (`UnknownCustomization` in the
            /// retired generate-caller.py).
            case unknownCustomization(String)
        }

        /// Caller-supplied `with:` keys, in canonical emission order.
        public static let approvedTypedInputs: [String] = [
            "platform-support", "embedded-target", "swift-version",
            "enable-private-repos", "test-filter",
            "docs-umbrella-module", "docs-umbrella-display-name",
            "docs-umbrella-bundle-id", "docs-umbrella-docc-path",
            "docs-exclude-modules", "docs-swift-version",
        ]

        /// The legacy four-name cross-org secret forward set (deleted at
        /// F15 after the two-name cutover rides the caller wave).
        public static let legacySecretNames: [String] = [
            "PRIVATE_REPO_TOKEN",
            "SWIFT_INSTITUTE_BOT_APP_CLIENT_ID",
            "SWIFT_INSTITUTE_BOT_APP_ID",
            "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
        ]

        /// The five linter rule-pack repositories whose leaf carries the
        /// ruled second job (notify-linter-republish: instant [CI-116]
        /// rule-pack freshness; principal ruling 2026-08-06 on #358).
        /// Exact coordinates — a new rule-pack repo is added here by an
        /// express edit, never inferred from its name.
        public static let linterRulePackRepositories: [String] = [
            "swift-primitives/swift-primitives-linter-rules",
            "swift-primitives/swift-linter-primitives",
            "swift-standards/swift-standards-linter-rules",
            "swift-foundations/swift-institute-linter-rules",
            "swift-foundations/swift-linter-rules",
        ]

        /// The terminal two-name credential profile is split across two
        /// GitHub contexts, not two secrets (plan §15; #394 comments
        /// 5204107123 and 5204206801, provisioned and read back
        /// 2026-08-06). The App id crosses as an org Actions **variable**
        /// and the private key as the only forwarded secret, so a
        /// generated leaf never names an id-shaped secret anywhere.
        ///
        /// The names a caller may forward under `secrets:`. Exactly one.
        /// The historical two-name spelling of this constant listed
        /// `SWIFT_INSTITUTE_BOT_APP_ID` here; that reading was measured
        /// FAIL at F13 (run 31097725224, job 92603630599 — the id was
        /// withheld from the secrets context because it is not a secret)
        /// and is superseded by the vars profile below, not withdrawn.
        public static let terminalSecretNames: [String] = [
            "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
        ]

        /// The names delivered through the `vars` context rather than
        /// `secrets`. Each of the four orgs that hosts a terminal caller
        /// carries this as an org Actions variable with the same value
        /// (the App's public client id) and `visibility: all`; F14
        /// asserts that invariant before any caller regeneration rather
        /// than assuming it (F13-receipt.json successor obligation).
        ///
        /// Equal values across orgs are what make the resolution safe
        /// while the K-01 cross-org `vars` hop stays UNMEASURED: caller-
        /// org and callee-org resolution cannot be distinguished by
        /// outcome when both resolve to the same literal.
        public static let terminalVariableNames: [String] = [
            "SWIFT_INSTITUTE_BOT_APP_ID",
        ]

        public let repository: String
        public let layer: Layer
        /// Ordered caller-supplied inputs; keys must come from
        /// `approvedTypedInputs`.
        public let inputs: [(key: String, value: String)]

        public init(
            repository: String, layer: Layer,
            inputs: [(key: String, value: String)] = []
        ) throws(Error) {
            guard repository.contains("/") else {
                throw .malformedRepository(repository)
            }
            self.repository = repository
            self.layer = layer
            self.inputs = inputs.filter { !$0.value.isEmpty }
        }

        public var owner: String {
            String(repository.prefix { $0 != "/" })
        }

        public var sameOrganization: Bool {
            owner == layer.wrapperOrganization
        }

        public static func == (lhs: Caller, rhs: Caller) -> Bool {
            lhs.repository == rhs.repository && lhs.layer == rhs.layer
                && lhs.inputs.elementsEqual(rhs.inputs, by: ==)
        }
    }
}
