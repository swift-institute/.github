extension CI.Contract {
    /// A temporary, upstream-availability classification for the containerized
    /// Linux legs of the Swift release floor.
    ///
    /// The floor's Linux legs run `swift:<floor>` — the official Docker Hub
    /// release image. When the floor is raised *ahead of* upstream publishing
    /// that image, `swift:<floor>` does not exist and every containerized leg
    /// dies at container init, before checkout (swift-institute/.github#491:
    /// the 6.4 floor of #485/#487 against a Docker Hub that returns 404 for
    /// both `swift:6.4` and `swift:6.4.0`).
    ///
    /// The repair is never a mutable substitute tag. It is one exception of
    /// the same class as `NightlyException`: an exact image identity, the
    /// upstream coordinate whose arrival retires it, and a recheck date that
    /// may not outlive the RC/stable boundary. `Plan` refuses to emit any leg
    /// unless this validates, so a stale or hand-loosened exception fails the
    /// run rather than quietly shipping an unknown toolchain.
    ///
    /// **Retiring it is a removal, not a rewrite.** The workflow's legs bind
    /// `needs.plan.outputs.linux-image` permanently; deleting the exception's
    /// three environment values (and the plan arguments carrying them) makes
    /// `resolve` fall through to `stableImage(swiftVersion:)` — `swift:6.4` —
    /// with no container, job, or validator edit anywhere.
    public struct ReleaseFloorException: Sendable, Equatable {
        public enum Error: Swift.Error, Equatable {
            case swiftVersion(String)
            case image(String)
            case upstreamRelease(String)
            case recheck(String)
            case beyondBoundary(recheck: String, boundary: String)
            case expired(recheck: String, today: String)
        }

        /// The RC/stable boundary this class of exception may never outlive.
        ///
        /// A recheck date beyond it is refused at validation rather than
        /// merely noted, because the failure mode of an image exception is
        /// silent: an expired pin keeps pulling and keeps passing, so nothing
        /// ever forces the question of whether the stable image has landed.
        public static let boundary = "2026-09-09"

        /// The Swift release floor this exception stands in for.
        public let swiftVersion: String
        /// The exact image identity the Linux legs run, by digest.
        public let image: String
        /// The upstream release whose publication retires this exception.
        public let upstreamRelease: String
        /// The date by which the exception must be rechecked or removed.
        public let recheck: String

        public init(
            swiftVersion: String, image: String, upstreamRelease: String, recheck: String
        ) {
            self.swiftVersion = swiftVersion
            self.image = image
            self.upstreamRelease = upstreamRelease
            self.recheck = recheck
        }

        /// The official release image for a floor, absent any exception.
        public static func stableImage(swiftVersion: String) -> String {
            "swift:\(swiftVersion)"
        }

        /// The upstream coordinate a floor's exception must name.
        public static func releaseCoordinate(swiftVersion: String) -> String {
            "https://github.com/swiftlang/swift/releases/tag/swift-\(swiftVersion)-RELEASE"
        }

        /// The image the containerized Linux legs must run for `swiftVersion`.
        ///
        /// `exception` absent — the ordinary, terminal state — is the official
        /// `swift:<floor>` image. Present, it must validate first: an
        /// exception that cannot justify itself never resolves to an image.
        public static func resolve(
            swiftVersion: String, exception: Self?, today: String
        ) throws(Error) -> String {
            guard let exception else { return stableImage(swiftVersion: swiftVersion) }
            try exception.validate(today: today)
            return exception.image
        }

        public func validate(today: String) throws(Error) {
            let components = swiftVersion.split(
                separator: ".", omittingEmptySubsequences: false)
            guard (2...3).contains(components.count),
                  components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
            else { throw .swiftVersion(swiftVersion) }

            let prefix = "swiftlang/swift@sha256:"
            let digest = String(image.dropFirst(prefix.count))
            guard image.hasPrefix(prefix), digest.count == 64,
                  digest.allSatisfy(\.isHexDigit)
            else { throw .image(image) }

            guard upstreamRelease == Self.releaseCoordinate(swiftVersion: swiftVersion)
            else { throw .upstreamRelease(upstreamRelease) }

            guard CI.Contract.isCalendarDate(recheck), CI.Contract.isCalendarDate(today)
            else { throw .recheck(recheck) }
            guard recheck <= Self.boundary
            else { throw .beyondBoundary(recheck: recheck, boundary: Self.boundary) }
            guard today <= recheck else { throw .expired(recheck: recheck, today: today) }
        }
    }
}
