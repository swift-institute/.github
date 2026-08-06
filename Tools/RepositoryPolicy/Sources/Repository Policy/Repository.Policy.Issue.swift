import Byte_Primitives
import FIPS_180_4
import Foundation

extension RepositoryPolicy {
    /// The versioned, body-owned portion of an Issue record. Native GitHub
    /// state and relationships are deliberately supplied separately.
    public enum Issue {}
}

extension RepositoryPolicy.Issue {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case goal = "Goal"
        case task = "Task"
    }

    public enum Status: String, Codable, CaseIterable, Sendable {
        case proposed = "Proposed"
        case assessed = "Assessed"
        case active = "Active"
        case blocked = "Blocked"
    }

    public enum NativeState: String, Codable, Sendable {
        case open
        case completed
        case notPlanned = "not-planned"
        case duplicate
    }

    public enum Finding: String, Codable, Sendable {
        case conforming
        case malformed
        case stale
        case superseded
        case unavailable
    }

    public struct Native: Codable, Equatable, Sendable {
        public let state: NativeState
        public let parent: String?
        public let relationships: [String]

        public init(state: NativeState, parent: String? = nil, relationships: [String] = []) {
            self.state = state
            self.parent = parent
            self.relationships = relationships.sorted()
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        public let kind: Kind
        public let owner: String
        public let status: Status
        public let grammarVersion: Int

        public init(kind: Kind, owner: String, status: Status, grammarVersion: Int) throws {
            guard grammarVersion == 1 else {
                throw Error.unsupportedVersion(grammarVersion)
            }
            guard Self.isCoordinate(owner) else {
                throw Error.invalidOwner(owner)
            }
            guard kind == .goal || status == .active || status == .blocked else {
                throw Error.invalidStatus(kind: kind, status: status)
            }
            self.kind = kind
            self.owner = owner
            self.status = status
            self.grammarVersion = grammarVersion
        }

        private static func isCoordinate(_ value: String) -> Bool {
            let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
        }
    }

    public struct Decision: Codable, Equatable, Sendable {
        public let grammarVersion: Int
        public let status: String
        public let supersededBy: String?

        public init(grammarVersion: Int, status: String, supersededBy: String? = nil) throws {
            guard grammarVersion == 1 else {
                throw Error.unsupportedVersion(grammarVersion)
            }
            guard ["proposed", "accepted", "rejected", "superseded"].contains(status) else {
                throw Error.invalidDecisionStatus(status)
            }
            guard (status == "superseded") == (supersededBy != nil) else {
                throw Error.invalidSupersession
            }
            self.grammarVersion = grammarVersion
            self.status = status
            self.supersededBy = supersededBy
        }
    }

    public struct CompactionCheckpoint: Codable, Equatable, Sendable {
        public let grammarVersion: Int
        public let source: String
        public let digest: String

        public init(grammarVersion: Int, source: String, digest: String) throws {
            guard grammarVersion == 1 else {
                throw Error.unsupportedVersion(grammarVersion)
            }
            guard !source.isEmpty, FIPS_180_4.SHA1.isDigestHex(digest) else {
                throw Error.invalidCheckpoint
            }
            self.grammarVersion = grammarVersion
            self.source = source
            self.digest = digest
        }
    }

    public struct TerminalReceipt: Codable, Equatable, Sendable {
        public let grammarVersion: Int
        public let revision: String
        public let verification: String

        public init(grammarVersion: Int, revision: String, verification: String) throws {
            guard grammarVersion == 1 else {
                throw Error.unsupportedVersion(grammarVersion)
            }
            guard FIPS_180_4.SHA1.isDigestHex(revision), !verification.isEmpty
            else {
                throw Error.invalidReceipt
            }
            self.grammarVersion = grammarVersion
            self.revision = revision
            self.verification = verification
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case duplicateField(String)
        case inactiveRecord
        case invalidCheckpoint
        case invalidDecisionStatus(String)
        case invalidDigest
        case invalidOwner(String)
        case invalidReceipt
        case invalidStatus(kind: Kind, status: Status)
        case invalidSupersession
        case missingField(String)
        case staleGuard
        case unsupportedVersion(Int)
    }

    public enum Parser {
        public static func record(_ body: String) throws -> Record {
            let fields = try fields(in: body, profile: .record)
            guard let kind = Kind(rawValue: try required("Kind", in: fields)) else {
                throw Error.missingField("Kind")
            }
            guard let status = Status(rawValue: try required("Status", in: fields)) else {
                throw Error.missingField("Status")
            }
            guard let version = Int(try required("Grammar version", in: fields)) else {
                throw Error.missingField("Grammar version")
            }
            return try Record(
                kind: kind,
                owner: try required("Owner coordinate", in: fields),
                status: status,
                grammarVersion: version
            )
        }

        public static func decision(_ body: String) throws -> Decision {
            let fields = try fields(in: body, profile: .decision)
            return try Decision(
                grammarVersion: Int(try required("Grammar version", in: fields)) ?? -1,
                status: try required("Decision status", in: fields),
                supersededBy: fields["Superseded by"]
            )
        }

        public static func checkpoint(_ body: String) throws -> CompactionCheckpoint {
            let fields = try fields(in: body, profile: .checkpoint)
            return try CompactionCheckpoint(
                grammarVersion: Int(try required("Grammar version", in: fields)) ?? -1,
                source: try required("Source", in: fields),
                digest: try required("Digest", in: fields)
            )
        }

        public static func receipt(_ body: String) throws -> TerminalReceipt {
            let fields = try fields(in: body, profile: .receipt)
            return try TerminalReceipt(
                grammarVersion: Int(try required("Grammar version", in: fields)) ?? -1,
                revision: try required("Revision", in: fields),
                verification: try required("Verification", in: fields)
            )
        }

        private enum Profile {
            case record, decision, checkpoint, receipt

            var fields: Set<String> {
                switch self {
                case .record: ["Kind", "Owner coordinate", "Status", "Grammar version"]
                case .decision: ["Grammar version", "Decision status", "Superseded by"]
                case .checkpoint: ["Grammar version", "Source", "Digest"]
                case .receipt: ["Grammar version", "Revision", "Verification"]
                }
            }
        }

        private static func fields(in body: String, profile: Profile) throws -> [String: String] {
            var result = [String: String]()
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            var index = 0
            while index < lines.count {
                let line = lines[index]
                guard line.hasPrefix("### ") else {
                    index += 1
                    continue
                }
                let name = String(line.dropFirst(4))
                guard profile.fields.contains(name) else {
                    index += 1
                    continue
                }
                guard result[name] == nil else { throw Error.duplicateField(name) }
                index += 1
                var value = ""
                while index < lines.count, !lines[index].hasPrefix("### ") {
                    let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        guard value.isEmpty else { throw Error.duplicateField(name) }
                        value = String(line)
                    }
                    index += 1
                }
                result[name] = value
            }
            return result
        }

        private static func required(_ name: String, in fields: [String: String]) throws -> String {
            guard let value = fields[name], !value.isEmpty else { throw Error.missingField(name) }
            return value
        }
    }

    public struct Input: Sendable {
        public let coordinate: String
        public let body: String?
        public let native: Native?
        public let decision: Decision?

        public init(coordinate: String, body: String?, native: Native?, decision: Decision? = nil) {
            self.coordinate = coordinate
            self.body = body
            self.native = native
            self.decision = decision
        }
    }

    public struct Report: Equatable, Sendable {
        public let coordinate: String
        public let finding: Finding
        public let message: String
    }

    public struct Page: Sendable {
        public let inputs: [Input]
        public let hasNextPage: Bool

        public init(inputs: [Input], hasNextPage: Bool) {
            self.inputs = inputs
            self.hasNextPage = hasNextPage
        }
    }

    /// Reconciliation is deterministic and report-only. It never changes an
    /// Issue, Project item, native relationship, or comment.
    public static func reconcile(_ inputs: [Input]) -> [Report] {
        inputs.sorted { $0.coordinate < $1.coordinate }.map { input in
            guard let body = input.body, let native = input.native else {
                return .init(
                    coordinate: input.coordinate,
                    finding: .unavailable,
                    message: "body or native state is unavailable"
                )
            }
            if input.decision?.status == "superseded" {
                return .init(
                    coordinate: input.coordinate,
                    finding: .superseded,
                    message: "decision record is superseded"
                )
            }
            do {
                let record = try Parser.record(body)
                if native.state != .open, record.status == .active {
                    return .init(
                        coordinate: input.coordinate,
                        finding: .stale,
                        message: "active body record disagrees with terminal native state"
                    )
                }
                return .init(
                    coordinate: input.coordinate,
                    finding: .conforming,
                    message: "record conforms to grammar v1"
                )
            } catch {
                return .init(
                    coordinate: input.coordinate,
                    finding: .malformed,
                    message: "record body does not conform to grammar v1"
                )
            }
        }
    }

    /// Flattens every fetched page before applying the same report-only
    /// decision, so API page boundaries cannot change the report.
    public static func reconcile(pages: [Page]) -> [Report] {
        reconcile(pages.flatMap(\.inputs))
    }

    /// A read of the current Issue body. `revision` is the HTTP entity tag
    /// returned with that body; the digest makes its content guard explicit in
    /// reports and command-line invocations.
    public struct Snapshot: Equatable, Sendable {
        public let coordinate: String
        public let revision: String
        public let body: String
        public let native: Native

        public init(coordinate: String, revision: String, body: String, native: Native) {
            self.coordinate = coordinate
            self.revision = revision
            self.body = body
            self.native = native
        }

        public var digest: String {
            FIPS_180_4.SHA1.digest(Array(body.utf8).map(Byte.init)).hex
        }
    }

    /// The sole pair of guards accepted by an apply operation. Both must
    /// describe the current body; a revision alone is not a content witness.
    public struct Guard: Equatable, Sendable {
        public let revision: String
        public let digest: String

        public init(revision: String, digest: String) throws {
            guard !revision.isEmpty, FIPS_180_4.SHA1.isDigestHex(digest) else {
                throw Error.invalidDigest
            }
            self.revision = revision
            self.digest = digest
        }
    }

    /// A deterministic, side-effect-free compaction result. The executor may
    /// update only `body` and append only `checkpoint`; comments and native
    /// GitHub state are intentionally absent from this value.
    public struct Compaction: Equatable, Sendable {
        public let `guard`: Guard
        public let body: String
        public let checkpoint: String

        public init(`guard`: Guard, body: String, checkpoint: String) {
            self.`guard` = `guard`
            self.body = body
            self.checkpoint = checkpoint
        }
    }

    public enum Compactor {
        /// Plans a rewrite only for an open, Active Issue whose supplied guard
        /// still names its current body. Calling this method never mutates an
        /// Issue or reads its history.
        public static func plan(snapshot: Snapshot, guard expected: Guard) throws -> Compaction? {
            guard snapshot.revision == expected.revision, snapshot.digest == expected.digest else {
                throw Error.staleGuard
            }
            guard snapshot.native.state == .open else { throw Error.inactiveRecord }
            let record = try Parser.record(snapshot.body)
            guard record.status == .active else { throw Error.inactiveRecord }

            let body = render(record)
            guard body != snapshot.body else { return nil }
            let checkpoint = try CompactionCheckpoint(
                grammarVersion: record.grammarVersion,
                source: snapshot.coordinate,
                digest: snapshot.digest
            )
            return .init(guard: expected, body: body, checkpoint: render(checkpoint))
        }

        public static func render(_ record: Record) -> String {
            """
            ### Kind

            \(record.kind.rawValue)

            ### Owner coordinate

            \(record.owner)

            ### Status

            \(record.status.rawValue)

            ### Grammar version

            \(record.grammarVersion)
            """
        }

        public static func render(_ checkpoint: CompactionCheckpoint) -> String {
            """
            ### Grammar version

            \(checkpoint.grammarVersion)

            ### Source

            \(checkpoint.source)

            ### Digest

            \(checkpoint.digest)
            """
        }
    }
}
