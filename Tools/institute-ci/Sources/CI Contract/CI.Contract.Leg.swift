extension CI.Contract {
    /// One matrix leg, identified by its job id. The leg set is open
    /// (advisory legs come and go); family classification and gating
    /// membership are the closed, semantic parts.
    public struct Leg: Sendable, Equatable, Hashable {
        public enum Family: String, Sendable, Equatable {
            case apple
            case linux
            case windows
        }

        public let id: String

        public init(_ id: String) {
            self.id = id
        }

        /// The platform family the platform-support filter keys on;
        /// nil for platform-neutral legs (quality gates, advisory).
        public var family: Family? {
            switch id {
            case "macos-release", "apple-simulator-build": .apple
            case "linux-release", "linux-nightly", "linux-6-4": .linux
            case "windows-release": .windows
            default: nil
            }
        }

        /// Gating legs — exactly ci-ok's needs minus `plan`.
        public var gating: Bool {
            switch id {
            case "format", "lint", "swift-linter",
                 "macos-release", "linux-release", "windows-release":
                true
            default:
                false
            }
        }

        /// The release build legs ci-ok requires at least one success from.
        public var buildLeg: Bool {
            switch id {
            case "macos-release", "linux-release", "windows-release": true
            default: false
            }
        }
    }
}
