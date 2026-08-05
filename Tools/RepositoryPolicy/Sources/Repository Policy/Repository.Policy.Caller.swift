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
        }

        public enum Error: Swift.Error, Equatable {
            case malformedRepository(String)
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

        /// The terminal two-name secret profile (FT1-frozen).
        public static let terminalSecretNames: [String] = [
            "SWIFT_INSTITUTE_BOT_APP_ID",
            "SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY",
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
