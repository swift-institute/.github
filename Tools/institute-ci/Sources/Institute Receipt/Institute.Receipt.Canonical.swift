public import Byte_Primitives
import FIPS_180_4
import Foundation

extension Institute.Receipt {
    /// The version-1 wire codec: canonical bytes in, canonical bytes out,
    /// and the digest taken over them.
    ///
    /// Canonical means UTF-8 JSON with lexicographically sorted object
    /// keys, no insignificant whitespace, LF termination, and every array
    /// ordered by its declared identity key — path, coordinate, numeric
    /// job id. That is not formatting preference: the receipt's whole
    /// value is that two independent readers agree on one byte string, so
    /// the digest of a record is a stable name for it. A serializer that
    /// merely produced *valid* JSON would produce a different digest per
    /// run and attest nothing.
    ///
    /// The key order is written out literally at each level rather than
    /// sorted at emission. It is a contract, so it should read as one and
    /// be reviewable as one; a `sort` call hides a change of contract
    /// inside a change of field name.
    ///
    /// Four families are reserved-empty in version 1 — `actions`,
    /// `containers`, `linter`, `revisions`. They are wire constants owned
    /// here rather than absent fields, because a consumer that cannot
    /// tell "not yet collected" from "collected and empty" is the
    /// measurement gap this contract exists to close; each is paired with
    /// a typed `Unmeasured` row naming why.
    public enum Canonical {}
}

extension Institute.Receipt.Canonical {
    /// The schema version every version-1 record declares.
    public static let schemaVersion = 1

    /// The canonical bytes of an attestation, LF-terminated.
    public static func bytes(of attestation: Institute.Receipt.Attestation) -> [Byte] {
        Array(text(of: attestation).utf8).map(Byte.init)
    }

    /// Lowercase hex SHA-256 of the canonical bytes, through the R37
    /// witness — the receipt's name.
    public static func digest(of attestation: Institute.Receipt.Attestation) -> String {
        FIPS_180_4.SHA256.digest(bytes(of: attestation)).hex
    }

    /// Lowercase hex SHA-256 of bytes already on disk, so a verifier
    /// digests what it read rather than what it re-encoded.
    public static func digest(of payload: [Byte]) -> String {
        FIPS_180_4.SHA256.digest(payload).hex
    }

    static func text(of attestation: Institute.Receipt.Attestation) -> String {
        let base = attestation.base
        let record = object([
            ("actions", "[]"),
            ("attestationStage", string(attestation.stage.rawValue)),
            ("baseReceiptDigest", optionalString(attestation.baseReceiptDigest)),
            ("containers", "[]"),
            ("jobs", array(ordered(base.jobs).map(job))),
            ("linter", "null"),
            ("referencedWorkflows",
             array(base.referencedWorkflows.sorted { $0.path < $1.path }
                .map(referencedWorkflow))),
            ("revisions", "null"),
            ("run", run(base.run)),
            ("schemaVersion", String(schemaVersion)),
            ("subject", subject(base)),
            ("unmeasured", array(base.unmeasured.sorted { $0.field < $1.field }
                .map(unmeasured))),
            ("verdict", string(attestation.verdict.rawValue)),
        ])
        return record + "\n"
    }

    /// Jobs by numeric id, the rows without one last, and otherwise in
    /// the order they were captured — a stable order, so two captures of
    /// the same run cannot canonicalize differently.
    private static func ordered(_ jobs: [Institute.Receipt.Job]) -> [Institute.Receipt.Job] {
        jobs.enumerated()
            .sorted { left, right in
                switch (left.element.id, right.element.id) {
                case (let first?, let second?):
                    first == second ? left.offset < right.offset : first < second
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): left.offset < right.offset
                }
            }
            .map(\.element)
    }

    private static func run(_ run: Institute.Receipt.Run) -> String {
        object([
            ("actor", optionalString(run.actor)),
            ("attempt", optionalNumber(run.attempt)),
            ("conclusion", optionalString(run.conclusion?.rawValue)),
            ("event", optionalString(run.event)),
            ("headBranch", optionalString(run.headBranch)),
            ("headRepository", optionalString(run.headRepository)),
            ("headSha", optionalString(run.headSha)),
            ("id", optionalNumber(run.id)),
            ("repository", optionalString(run.repository)),
            ("workflowPath", optionalString(run.workflowPath)),
        ])
    }

    private static func subject(_ base: Institute.Receipt.Preterminal) -> String {
        object([
            ("repository", string(base.subjectRepository)),
            ("sha", string(base.subjectSha)),
            ("visibility", string(base.subjectVisibility)),
        ])
    }

    private static func referencedWorkflow(
        _ hop: Institute.Receipt.ReferencedWorkflow
    ) -> String {
        object([
            ("path", string(hop.path)),
            ("ref", string(hop.ref)),
            ("sha", string(hop.sha)),
        ])
    }

    private static func job(_ job: Institute.Receipt.Job) -> String {
        object([
            ("conclusion", optionalString(job.conclusion?.rawValue)),
            ("id", optionalNumber(job.id)),
            ("mandatory", job.mandatory ? "true" : "false"),
            ("name", string(job.name)),
            ("runnerLabels", array(job.runnerLabels.map(string))),
            ("selected", job.selected ? "true" : "false"),
        ])
    }

    private static func unmeasured(_ row: Institute.Receipt.Unmeasured) -> String {
        object([
            ("field", string(row.field)),
            ("reason", string(row.reason)),
        ])
    }

    private static func object(_ members: [(String, String)]) -> String {
        "{" + members.map { "\(string($0.0)):\($0.1)" }.joined(separator: ",") + "}"
    }

    private static func array(_ elements: [String]) -> String {
        "[" + elements.joined(separator: ",") + "]"
    }

    private static func optionalString(_ value: String?) -> String {
        value.map(string) ?? "null"
    }

    private static func optionalNumber(_ value: Int?) -> String {
        value.map(String.init) ?? "null"
    }

    /// A JSON string.
    ///
    /// Non-ASCII scalars are emitted as themselves, not as `\u` escapes;
    /// the escape set is exactly the one the retired canonicalizer used
    /// (`json.dumps(..., ensure_ascii=False)`), so a byte comparison
    /// against it measures the record rather than the encoder's taste.
    private static func string(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case let scalar where scalar.value < 0x20:
                result += "\\u" + hexadecimal(scalar.value)
            case let scalar:
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func hexadecimal(_ value: UInt32) -> String {
        let digits = Array("0123456789abcdef")
        var result = ""
        for shift in stride(from: 12, through: 0, by: -4) {
            result.append(digits[Int((value >> UInt32(shift)) & 0xF)])
        }
        return result
    }
}

extension Institute.Receipt.Canonical {
    /// The one failure reading a canonical record may raise.
    public enum Error: Swift.Error, Sendable, Equatable {
        case malformed(String)
    }

    /// Reads a canonical record back into the typed attestation.
    ///
    /// The collector needs this: it fetches a preterminal record produced
    /// by another run and must re-emit it with only the terminal facts
    /// replaced. Reading into the typed value and re-encoding — rather
    /// than mutating a raw JSON tree in place, as the retired collector
    /// did — is what makes "only the terminal facts changed" a property
    /// of the type rather than a property of the diff.
    public static func attestation(
        from payload: [Byte]
    ) throws(Error) -> Institute.Receipt.Attestation {
        let data = Data(payload.map(\.underlying))
        // swift-linter:disable:next try optional
        // REASON: JSONSerialization.jsonObject throws untyped; the refusal it maps to is this function's own typed error.
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let record = object as? [String: Any]
        else { throw .malformed("record is not a JSON object") }
        guard let stageName = record["attestationStage"] as? String,
              let stage = Institute.Receipt.Stage(rawValue: stageName)
        else { throw .malformed("attestationStage is absent or unrecognised") }
        guard let verdictName = record["verdict"] as? String,
              let verdict = Institute.Receipt.Verdict(rawValue: verdictName)
        else { throw .malformed("verdict is absent or unrecognised") }
        guard let runObject = record["run"] as? [String: Any] else {
            throw .malformed("run is absent")
        }
        guard let subjectObject = record["subject"] as? [String: Any] else {
            throw .malformed("subject is absent")
        }
        let run = Institute.Receipt.Run(
            id: runObject["id"] as? Int,
            attempt: runObject["attempt"] as? Int,
            headSha: runObject["headSha"] as? String,
            event: runObject["event"] as? String,
            conclusion: (runObject["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) },
            repository: runObject["repository"] as? String,
            workflowPath: runObject["workflowPath"] as? String,
            actor: runObject["actor"] as? String,
            headRepository: runObject["headRepository"] as? String,
            headBranch: runObject["headBranch"] as? String)
        let referenced = (record["referencedWorkflows"] as? [[String: Any]] ?? []).map {
            Institute.Receipt.ReferencedWorkflow(
                path: $0["path"] as? String ?? "",
                ref: $0["ref"] as? String ?? "",
                sha: $0["sha"] as? String ?? "")
        }
        let jobs = (record["jobs"] as? [[String: Any]] ?? []).map {
            Institute.Receipt.Job(
                id: $0["id"] as? Int,
                name: $0["name"] as? String ?? "",
                conclusion: ($0["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) },
                selected: $0["selected"] as? Bool ?? false,
                mandatory: $0["mandatory"] as? Bool ?? false,
                runnerLabels: $0["runnerLabels"] as? [String] ?? [])
        }
        let unmeasured = (record["unmeasured"] as? [[String: Any]] ?? []).map {
            Institute.Receipt.Unmeasured(
                field: $0["field"] as? String ?? "",
                reason: $0["reason"] as? String ?? "")
        }
        return .init(
            base: .init(
                run: run,
                subjectRepository: subjectObject["repository"] as? String ?? "",
                subjectSha: subjectObject["sha"] as? String ?? "",
                subjectVisibility: subjectObject["visibility"] as? String ?? "",
                referencedWorkflows: referenced,
                jobs: jobs,
                jobsTotalCount: nil,
                unmeasured: unmeasured),
            stage: stage,
            baseReceiptDigest: record["baseReceiptDigest"] as? String,
            verdict: verdict)
    }
}
