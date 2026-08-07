public import Byte_Primitives
import Foundation

extension Institute.Receipt {
    /// Reads the run object and paginated jobs collection an aggregate
    /// job fetched **for its own run** into a preterminal attestation.
    ///
    /// Everything this owner may not do is as much of the contract as
    /// what it does. It never calls GitHub, never expands a matrix,
    /// never evaluates a workflow expression, and never asserts a
    /// terminal conclusion — because it runs *inside* the run it
    /// describes, where those answers do not exist yet. Each one it
    /// cannot answer becomes a typed `Unmeasured` row naming the field
    /// and why, so the record is complete about its own incompleteness.
    ///
    /// The P20 control lives here: a run object exposing an empty or
    /// unavailable `referenced_workflows` collection makes the receipt
    /// `UNMEASURED`, and the producing aggregate must fail on it. An
    /// empty reusable-workflow chain is precisely the evidence gap the
    /// historical false-success variant accepted silently, and it is
    /// never repaired by reading current `main`.
    public enum Capture {}
}

extension Institute.Receipt.Capture {
    /// Whether an empty reusable-workflow chain is refused.
    ///
    /// `historicallyAccepted` reproduces the shape that shipped before
    /// P20 — a clean `preterminal` verdict over evidence that was never
    /// gathered. It exists so the mandatory negative control can observe
    /// the old behavior failing; no production caller selects it, and no
    /// CLI face exposes it.
    public enum EmptyChain: Sendable, Equatable {
        case refused
        case historicallyAccepted
    }

    public enum Error: Swift.Error, Sendable, Equatable {
        case malformed(document: String, reason: String)
        case subjectShaNotFull(String)
    }

    /// The reserved-empty families of version 1, each with the reason it
    /// is not resolvable from the run and jobs objects at in-run capture.
    static let reservedFamilies: [(String, String)] = [
        ("actions",
         "selected action coordinates are not resolvable from the run/jobs objects at in-run capture; terminal resolution is collector scope"),
        ("containers",
         "container image digests are not resolvable from the run/jobs objects at in-run capture"),
        ("linter",
         "linter release/authority/checksum identity is not exposed to the aggregate at in-run capture"),
        ("revisions",
         "workspace/policy/fixture revisions and the effective-inventory digest await the TX1/TX3 typed adapters"),
    ]

    /// The preterminal attestation for a run, from the two documents the
    /// aggregate fetched about itself.
    public static func attestation(
        runJSON: [Byte],
        jobsJSON: [Byte],
        plannedGating: [String],
        subjectRepository: String,
        subjectSha: String,
        subjectVisibility: String,
        emptyChain: EmptyChain = .refused
    ) throws(Error) -> Institute.Receipt.Attestation {
        guard subjectSha.count == 40 else { throw .subjectShaNotFull(subjectSha) }
        let run = try object(runJSON, document: "run")
        let jobs = try jobRows(jobsJSON)
        return attestation(
            run: run, jobs: jobs, plannedGating: plannedGating,
            subjectRepository: subjectRepository, subjectSha: subjectSha,
            subjectVisibility: subjectVisibility, emptyChain: emptyChain)
    }

    /// The same capture over already-decoded documents — the seam the
    /// tests drive, so the record is exercised without a file on disk.
    public static func attestation(
        run: [String: Any],
        jobs: [[String: Any]],
        plannedGating: [String],
        subjectRepository: String,
        subjectSha: String,
        subjectVisibility: String,
        emptyChain: EmptyChain = .refused
    ) -> Institute.Receipt.Attestation {
        var unmeasured: [Institute.Receipt.Unmeasured] = []

        func measured<Value>(_ value: Value?, _ field: String) -> Value? {
            if value == nil {
                unmeasured.append(.init(field: field, reason: "absent from run object"))
            }
            return value
        }

        let referenced = (run["referenced_workflows"] as? [[String: Any]] ?? [])
            .map {
                Institute.Receipt.ReferencedWorkflow(
                    path: $0["path"] as? String ?? "",
                    ref: $0["ref"] as? String ?? "",
                    sha: $0["sha"] as? String ?? "")
            }
        if referenced.isEmpty {
            unmeasured.append(
                .init(
                    field: "referencedWorkflows",
                    reason: "run object exposed an empty/unavailable referenced_workflows collection; the reusable-workflow chain is unmeasured and is never replaced by a read of current main"))
        }

        let gating = Set(plannedGating)
        var rows: [Institute.Receipt.Job] = []
        for job in jobs {
            let name = job["name"] as? String ?? ""
            // The aggregate's own-run jobs collection carries flattened
            // names ("ci-ok", "Plan (…)", "macos-release …"); whether a
            // job is gating is read from the Plan-declared list by
            // leading token, never by matching the whole flattened name.
            let leading = name.split(separator: " ", maxSplits: 1).first.map(String.init) ?? name
            let mandatory = gating.contains(leading)
            let identifier = job["id"] as? Int
            let conclusion = (job["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) }
            if conclusion == nil {
                unmeasured.append(
                    .init(
                        field: "jobs[\(identifier.map(String.init) ?? "?")].conclusion",
                        reason: "unavailable at in-run capture (job not terminal while the aggregate observes its own run)"))
            }
            rows.append(
                .init(
                    id: identifier,
                    name: name,
                    conclusion: conclusion,
                    selected: mandatory || (conclusion != nil && conclusion != .skipped),
                    mandatory: mandatory,
                    runnerLabels: job["labels"] as? [String] ?? []))
        }
        let conclusion = (run["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) }
        if conclusion == nil {
            unmeasured.append(
                .init(
                    field: "run.conclusion",
                    reason: "unavailable at in-run capture (the run cannot be terminal while its own aggregate job executes)"))
        }

        let identity = Institute.Receipt.Run(
            id: measured(run["id"] as? Int, "run.id"),
            attempt: measured(run["run_attempt"] as? Int, "run.attempt"),
            headSha: measured(run["head_sha"] as? String, "run.headSha"),
            event: measured(run["event"] as? String, "run.event"),
            conclusion: conclusion,
            repository: measured(
                (run["repository"] as? [String: Any])?["full_name"] as? String,
                "run.repository"),
            workflowPath: measured(run["path"] as? String, "run.workflowPath"),
            actor: measured((run["actor"] as? [String: Any])?["login"] as? String, "run.actor"),
            headRepository: measured(
                (run["head_repository"] as? [String: Any])?["full_name"] as? String,
                "run.headRepository"),
            headBranch: run["head_branch"] as? String)

        for (field, reason) in reservedFamilies {
            unmeasured.append(.init(field: field, reason: reason))
        }

        let verdict: Institute.Receipt.Verdict =
            referenced.isEmpty && emptyChain == .refused ? .unmeasured : .preterminal
        return .init(
            base: .init(
                run: identity,
                subjectRepository: subjectRepository,
                subjectSha: subjectSha,
                subjectVisibility: subjectVisibility,
                referencedWorkflows: referenced,
                jobs: rows,
                jobsTotalCount: nil,
                unmeasured: unmeasured.sorted { $0.field < $1.field }),
            stage: .preterminal,
            baseReceiptDigest: nil,
            verdict: verdict)
    }

    static func object(_ payload: [Byte], document: String) throws(Error) -> [String: Any] {
        let data = Data(payload.map(\.underlying))
        // swift-linter:disable:next try optional
        // REASON: JSONSerialization.jsonObject throws untyped; the refusal it maps to is this function's own typed error.
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            throw .malformed(document: document, reason: "not valid JSON")
        }
        guard let object = decoded as? [String: Any] else {
            throw .malformed(document: document, reason: "not a JSON object")
        }
        return object
    }

    /// The jobs collection, in either shape the aggregate produces: the
    /// paginated `{"jobs": […]}` document, or a bare array.
    static func jobRows(_ payload: [Byte]) throws(Error) -> [[String: Any]] {
        let data = Data(payload.map(\.underlying))
        // swift-linter:disable:next try optional
        // REASON: JSONSerialization.jsonObject throws untyped; the refusal it maps to is this function's own typed error.
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else {
            throw .malformed(document: "jobs", reason: "not valid JSON")
        }
        if let object = decoded as? [String: Any] {
            return object["jobs"] as? [[String: Any]] ?? []
        }
        return decoded as? [[String: Any]] ?? []
    }
}
