// Thin CLI mapping only; owns no predicate (annex: Institute CI Command).
import Byte_Primitives
import CI_Contract
import Canon
import CI_Validation
import CI_Workflow
import Foundation
import Institute_Receipt

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("institute-ci: \(message)\n".utf8))
    exit(2)
}

/// Every value of a repeatable flag, in the order given.
func values(_ flag: String, in arguments: [String]) -> [String] {
    var found: [String] = []
    for (index, argument) in arguments.enumerated()
    where argument == flag && index + 1 < arguments.count {
        found.append(arguments[index + 1])
    }
    return found
}

/// An `alias=path` pair, as the canon roots are given.
func aliased(_ text: String) -> (alias: String, path: String)? {
    guard let split = text.firstIndex(of: "=") else { return nil }
    return (String(text[..<split]), String(text[text.index(after: split)...]))
}

func value(_ flag: String, in arguments: [String]) -> String {
    guard let index = arguments.firstIndex(of: flag),
          index + 1 < arguments.count else { return "" }
    return arguments[index + 1]
}

switch arguments.first {
case "plan":
    let rest = Array(arguments.dropFirst())
    do {
        let plan = try CI.Contract.Plan(
            forcedTier: value("--tier", in: rest),
            ref: value("--ref", in: rest),
            headMessage: value("--head-message", in: rest),
            event: value("--event", in: rest),
            platformSupport: value("--platform-support", in: rest),
            lintBundle: value("--lint-bundle", in: rest))
        let payload: [String: Any] = [
            "tier": plan.tier.rawValue,
            "legs": plan.legs.map(\.id).joined(separator: ","),
            "gating": plan.gating.map(\.id).joined(separator: ","),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } catch {
        FileHandle.standardError.write(Data("institute-ci: plan refused: \(error)\n".utf8))
        exit(1)
    }
case "aggregate":
    let rest = Array(arguments.dropFirst())
    let needsJSON = value("--needs-json", in: rest)
    guard let needsData = needsJSON.data(using: .utf8),
          let needs = (try? JSONSerialization.jsonObject(with: needsData)) as? [String: [String: Any]] else {
        fail("aggregate requires --needs-json '{job: {result: ...}}'")
    }
    var results: [String: String] = [:]
    for (job, object) in needs where job != "plan" {
        results[job] = object["result"] as? String ?? ""
    }
    let verdict = CI.Contract.AggregateVerdict(
        planResult: needs["plan"]?["result"] as? String ?? "",
        results: results,
        gating: value("--gating", in: rest).split(separator: ",").map(String.init),
        subjectRepository: value("--subject-repository", in: rest),
        subjectSha: value("--subject-sha", in: rest),
        tier: value("--tier", in: rest),
        requireFullTier: rest.contains("--require-full-tier"))
    for finding in verdict.findings {
        FileHandle.standardError.write(Data("institute-ci: \(finding)\n".utf8))
    }
    print(verdict.pass ? "pass" : "fail")
    exit(verdict.pass ? 0 : 1)
case "bootstrap-identity", "bootstrap-manifest", "bootstrap-verify":
    let rest = Array(arguments.dropFirst())
    let identity = Institute.Receipt.Bootstrap.Identity(
        workspaceRevision: value("--workspace-revision", in: rest),
        sourcesRevision: value("--sources-revision", in: rest),
        toolchain: value("--toolchain", in: rest),
        operatingSystem: value("--os", in: rest),
        architecture: value("--arch", in: rest),
        provisioning: value("--provisioning", in: rest)
            .split(separator: ",").map(String.init))
    do throws(Institute.Receipt.Bootstrap.Identity.ValidationError) {
        try identity.validate()
    } catch {
        FileHandle.standardError.write(
            Data("institute-ci: bootstrap identity refused: \(error)\n".utf8))
        exit(1)
    }
    func identityJSON(_ identity: Institute.Receipt.Bootstrap.Identity) -> [String: Any] {
        [
            "workspaceRevision": identity.workspaceRevision,
            "sourcesRevision": identity.sourcesRevision,
            "toolchain": identity.toolchain,
            "operatingSystem": identity.operatingSystem,
            "architecture": identity.architecture,
            "provisioning": identity.provisioning.sorted(),
        ]
    }
    switch arguments.first {
    case "bootstrap-identity":
        var payload = identityJSON(identity)
        payload["key"] = identity.digest
        let data = try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    case "bootstrap-manifest":
        let root = value("--root", in: rest)
        let paths = value("--executables", in: rest)
            .split(separator: ",").map(String.init)
        var executables: [[String: Any]] = []
        for path in paths {
            guard let data = FileManager.default.contents(atPath: root + "/" + path) else {
                fail("bootstrap-manifest: unreadable executable \(path)")
            }
            let executable = Institute.Receipt.Bootstrap.Manifest.Executable(
                path: path, bytes: [UInt8](data).map(Byte.init))
            executables.append(["path": executable.path, "digest": executable.digest])
        }
        if executables.isEmpty { fail("bootstrap-manifest: no executables") }
        let payload: [String: Any] = [
            "identity": identityJSON(identity),
            "key": identity.digest,
            "executables": executables,
            "producerRun": value("--producer-run", in: rest),
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    case "bootstrap-verify":
        let root = value("--root", in: rest)
        let manifestPath = value("--manifest", in: rest)
        guard let manifestData = FileManager.default.contents(atPath: manifestPath),
              let object = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any],
              let identityObject = object["identity"] as? [String: Any],
              let key = object["key"] as? String,
              let executableObjects = object["executables"] as? [[String: Any]],
              let producerRun = object["producerRun"] as? String
        else {
            fail("bootstrap-verify: unreadable or malformed manifest")
        }
        let recorded = Institute.Receipt.Bootstrap.Identity(
            workspaceRevision: identityObject["workspaceRevision"] as? String ?? "",
            sourcesRevision: identityObject["sourcesRevision"] as? String ?? "",
            toolchain: identityObject["toolchain"] as? String ?? "",
            operatingSystem: identityObject["operatingSystem"] as? String ?? "",
            architecture: identityObject["architecture"] as? String ?? "",
            provisioning: identityObject["provisioning"] as? [String] ?? [])
        let manifest = Institute.Receipt.Bootstrap.Manifest(
            identity: recorded,
            key: key,
            executables: executableObjects.map {
                .init(path: $0["path"] as? String ?? "",
                      digest: $0["digest"] as? String ?? "")
            },
            producerRun: producerRun)
        do throws(Institute.Receipt.Bootstrap.Manifest.VerificationError) {
            try manifest.verify(against: identity) { path in
                FileManager.default.contents(atPath: root + "/" + path)
                    .map { [UInt8]($0).map(Byte.init) }
            }
        } catch {
            FileHandle.standardError.write(
                Data("institute-ci: bootstrap cache entry refused (fail closed): \(error)\n".utf8))
            exit(1)
        }
        print("verified: key \(identity.digest), \(executableObjects.count) executable(s), producer run \(producerRun)")
    default:
        fail("unreachable")
    }
case "validate":
    // The rule-invocation face: one validator, one repository, TSV on
    // stdout. Argument order and the TSV shape match the retired
    // `python3 validate-<rule>.py <owner/name> <repo-root>` invocation so
    // `validate-base.yml` needs no change beyond the command it runs.
    let rest = Array(arguments.dropFirst())
    let rule = CI.Validation.Rule(value("--rule", in: rest))
    guard let validator = CI.Validation.Registry.validator(for: rule) else {
        fail("validate: no Swift validator is registered for rule '\(rule)'")
    }
    let subject = CI.Validation.Subject(
        repository: value("--repository", in: rest), root: value("--root", in: rest))
    let run = CI.Validation.Run.validate(validator, of: subject)
    if let defect = run.defect {
        FileHandle.standardError.write(Data("institute-ci: \(defect.message)\n".utf8))
    }
    for finding in run.findings { print(finding.tsv) }
    exit(run.exitCode)

case "workflow-json":
    // Canonical JSON of one workflow document, as the reader sees it.
    // The face the reader is proved through: comparable against any
    // other YAML implementation's canonical rendering of the same file,
    // which is a far wider check than comparing one rule's findings.
    let rest = Array(arguments.dropFirst())
    let path = value("--file", in: rest)
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("workflow-json: unreadable file \(path)")
    }
    do throws(CI.Workflow.YAML.Error) {
        let document = try CI.Workflow.Document(
            name: (path as NSString).lastPathComponent,
            text: String(decoding: data, as: UTF8.self))
        print(CI.Workflow.YAML.Canonical.json(document.root))
    } catch {
        FileHandle.standardError.write(Data("institute-ci: \(error.message)\n".utf8))
        exit(1)
    }

case "check-canon":
    // The canon guard, replacing the retired `check-canon.sh` /
    // `check-canon.py` pair. One semantic, so one command: the wrapper's
    // contribution was the sanctioned root set and the developer-root
    // derivation, and that is argument defaulting, which lives here.
    let rest = Array(arguments.dropFirst())
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let developerRoot = value("--dev-root", in: rest).isEmpty
        ? "\(home)/Developer" : value("--dev-root", in: rest)
    // The three unified gate roots plus Workspace/CLAUDE.md, per the
    // 2026-07-05 gate-root unification ruling. The
    // `swift-institute/Workspace` coordinate is the current one and is
    // carried as-is; the Launch Programme's census repoints it.
    let declaredRoots = values("--root", in: rest).compactMap(aliased)
    let roots = declaredRoots.isEmpty
        ? [
            (alias: "institute", path: "\(developerRoot)/swift-institute/Skills"),
            (alias: "engagement", path: "\(developerRoot)/swift-institute/Engagement/Skills"),
            (alias: "rule", path: "\(developerRoot)/rule-institute/Skills"),
        ]
        : declaredRoots
    let declaredFiles = values("--file", in: rest).compactMap(aliased)
    let files = declaredRoots.isEmpty && declaredFiles.isEmpty
        ? [
            (
                alias: "workspace:CLAUDE.md",
                path: "\(developerRoot)/swift-institute/Workspace/CLAUDE.md"
            )
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
        : declaredFiles
    let corpus = Canon.Corpus.read(roots: roots, files: files)
    guard !corpus.documents.isEmpty else {
        // Exit 2, not a clean report. A run that found no corpus has
        // measured nothing, and reporting zero findings would be the
        // silent no-op every gate in this repository exists to prevent.
        FileHandle.standardError.write(Data("::error::check-canon: no corpus files found\n".utf8))
        exit(2)
    }
    let configuration = value("--configuration", in: rest).isEmpty
        ? ".github/scripts" : value("--configuration", in: rest)
    let audit = Canon.Audit(
        corpus: corpus,
        baseline: .read(at: "\(configuration)/.check-canon-baseline"),
        allowlist: .read(at: "\(configuration)/.check-canon-allowlist"),
        developerRoot: developerRoot)
    let selected = values("--check", in: rest).compactMap(Canon.Check.init(rawValue:))
    let report = audit.run(selected.isEmpty ? nil : selected)
    if rest.contains("--emit-baseline") {
        for entry in report.baselineEntries { print(entry) }
        exit(0)
    }
    let enforcing = rest.contains("--enforce")
    for line in report.lines(enforcing: enforcing) { print(line) }
    // `--enforce` keeps exit 1 on a non-baselined finding. The 0/2
    // normalisation the port adopted applies to validators aggregated by
    // `validate-base.yml`; this is a standalone gate whose caller —
    // `sync-skills.sh` — aborts a corpus sync on that 1, and normalising
    // it away would silently disarm the gate.
    exit(enforcing && !report.isClean ? 1 : 0)

case "canon-rule-count":
    // The Swift owner of `check-rule-count.sh`. Counts; does not judge.
    let rest = Array(arguments.dropFirst())
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let declared = values("--root", in: rest)
    let roots =
        (declared.isEmpty
            ? [
                "\(home)/Developer/swift-institute/Skills",
                "\(home)/Developer/swift-primitives/Skills",
                "\(home)/Developer/swift-primitives/swift-memory-primitives/Skills",
                "\(home)/Developer/swift-primitives/swift-index-primitives/Skills",
            ]
            : declared)
        .filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    do throws(Canon.Census.Error) {
        let census = try Canon.Census.taken(over: roots)
        print("Skill rule count across \(roots.count) root(s):")
        print("  heading-form (### [ID]): \(census.headingForm)")
        print("  table-row form  (| [ID] |): \(census.tableForm)")
        print("  union (per [SKILL-CREATE-005c]): \(census.union)")
    } catch {
        FileHandle.standardError.write(Data("::error::no skill roots found\n".utf8))
        exit(2)
    }

case "validate-fixtures":
    // The harness face — the Swift owner of `.github/scripts/tests/run.sh`.
    let rest = Array(arguments.dropFirst())
    let root = value("--corpus", in: rest)
    if root.isEmpty { fail("validate-fixtures requires --corpus <fixtures-dir>") }
    let harness = CI.Validation.Harness(corpus: .init(root: root))
    let report: CI.Validation.Harness.Report
    do throws(CI.Validation.EnvironmentDefect) {
        report = try harness.run(matching: value("--rule-prefix", in: rest))
    } catch {
        fail(error.message)
    }
    for outcome in report.outcomes { print("  " + outcome.summary) }
    print("")
    print("Total: \(report.satisfied.count) passed, \(report.unsatisfied.count) failed")
    if !report.unownedRuleDirectories.isEmpty {
        // Named, not silently skipped. `run.sh` failed the run on any
        // unregistered rule directory; during the port that residue is
        // expected, so it is reported and gated by --require-complete.
        print(
            "Awaiting a Swift validator (\(report.unownedRuleDirectories.count)): "
                + report.unownedRuleDirectories.joined(separator: ", "))
    }
    let complete = rest.contains("--require-complete")
    exit((complete ? report.isComplete : report.isSatisfied) ? 0 : 1)

default:
    fail(
        "usage: institute-ci plan|aggregate|validate|validate-fixtures|workflow-json"
            + "|check-canon|canon-rule-count"
            + "|bootstrap-identity|bootstrap-manifest|bootstrap-verify ...")
}
