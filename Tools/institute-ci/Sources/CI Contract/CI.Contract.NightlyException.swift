extension CI.Contract {
    /// A temporary, external-defect classification for the Swift main nightly.
    ///
    /// Nightly is never advisory merely because it is nightly: the exact image,
    /// upstream defect, and recheck date must all be recorded and valid.
    ///
    /// Expiry semantics are class-aware (ruled 2026-08-10, .github#488;
    /// adversarial review by the Launch coordinator on the same issue). This
    /// exception classifies an ADVISORY leg — one that is `continue-on-error`
    /// and excluded from ci-ok's needs — so its expiry must not fail the
    /// fleet's required check: the safe degraded state for an advisory leg
    /// whose classification lapsed is that the leg does not run. Expiry
    /// therefore DESCHEDULES the leg fleet-wide, with a typed record, while
    /// the control-plane owner repository alone stays fail-closed red until
    /// the exception is re-ratified — the forcing function survives,
    /// localized to the owner. Gating-class exceptions
    /// (``ReleaseFloorException``) keep unconditional fail-closed expiry.
    ///
    /// The advisory/gating class is DERIVED from the leg's mechanical facts
    /// (``Leg/gating`` is exactly ci-ok's needs minus plan), never authored:
    /// an exception claiming to classify a gating leg is rejected fail-closed
    /// regardless of dates. The leg's `continue-on-error` posture is the
    /// workflow-side half of the same fact, enforced by
    /// `validate-continue-on-error` ([CI-105]).
    public struct NightlyException: Sendable, Equatable {
        public enum Error: Swift.Error, Equatable {
            case image(String)
            case upstreamIssue(String)
            case recheck(String)
            case expired(recheck: String, today: String)
            /// The exception claims to classify a leg that is gating
            /// (mechanically: in ci-ok's needs). Advisory-class expiry
            /// semantics must not be obtainable for a gating obligation.
            case classifiedGatingLeg(String)
        }

        /// How an in-date-format, well-formed exception applies to this run.
        public enum Disposition: Sendable, Equatable {
            /// The exception is current: the advisory leg is schedulable.
            case active
            /// The recheck date has passed on a non-owner subject: the
            /// advisory leg is descheduled with this typed record, and the
            /// run otherwise proceeds.
            case expired(recheck: String, today: String)
        }

        /// The control-plane repository that owns this exception. Its own
        /// plan stays fail-closed red on expiry so a lapsed exception still
        /// forces a ruling — with a one-repository blast radius instead of
        /// the fleet's.
        public static let owner = "swift-institute/.github"

        /// The advisory leg this exception classifies.
        public static let classifiedLeg = Leg("linux-nightly")

        public let image: String
        public let upstreamIssue: String
        public let recheck: String

        public init(image: String, upstreamIssue: String, recheck: String) {
            self.image = image
            self.upstreamIssue = upstreamIssue
            self.recheck = recheck
        }

        /// Validates the record and resolves this run's disposition.
        ///
        /// Malformed fields (image not an exact digest, upstream issue not a
        /// swiftlang/swift issue URL, dates not `YYYY-MM-DD`) always throw:
        /// those are authoring defects, not calendar events, and they fail
        /// closed everywhere. A well-formed but expired exception throws only
        /// when `subjectRepository` is the owner; on any other subject it
        /// returns ``Disposition/expired(recheck:today:)`` so the plan
        /// deschedules the classified leg and records why.
        public func disposition(
            today: String, subjectRepository: String
        ) throws(Error) -> Disposition {
            guard !Self.classifiedLeg.gating else {
                throw .classifiedGatingLeg(Self.classifiedLeg.id)
            }
            let prefix = "swiftlang/swift@sha256:"
            let digest = String(image.dropFirst(prefix.count))
            guard image.hasPrefix(prefix), digest.count == 64,
                  digest.allSatisfy(\.isHexDigit)
            else { throw .image(image) }
            let issuePrefix = "https://github.com/swiftlang/swift/issues/"
            let issue = String(upstreamIssue.dropFirst(issuePrefix.count))
            guard upstreamIssue.hasPrefix(issuePrefix), !issue.isEmpty,
                  issue.allSatisfy(\.isNumber)
            else { throw .upstreamIssue(upstreamIssue) }
            guard Self.isDate(recheck), Self.isDate(today)
            else { throw .recheck(recheck) }
            guard today > recheck else { return .active }
            guard subjectRepository != Self.owner else {
                throw .expired(recheck: recheck, today: today)
            }
            return .expired(recheck: recheck, today: today)
        }

        /// Delegates to the one owner of the `YYYY-MM-DD` shape
        /// (`CI.Contract.isCalendarDate`). Same predicate, same verdicts —
        /// this exception's semantics are unchanged.
        static func isDate(_ text: String) -> Bool { CI.Contract.isCalendarDate(text) }
    }
}
