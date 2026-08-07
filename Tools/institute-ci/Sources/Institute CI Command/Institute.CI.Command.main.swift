// Thin CLI mapping only; owns no predicate (annex: Institute CI Command).
import Byte_Primitives
import CI_Contract
import CI_Symbol_Graph
import CI_Validation
import CI_Workflow
import Foundation
import Institute_Receipt

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("institute-ci: \(message)\n".utf8))
    exit(2)
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

case "symbol-graph-umbrella":
    // Patch and isolate an umbrella module's symbol graph for
    // `docc convert --additional-symbol-graph-dir` ([DOC-019a]).
    let rest = Array(arguments.dropFirst())
    let sourceDirectory = value("--symbol-graph-dir", in: rest)
    let outputDirectory = value("--output-dir", in: rest)
    let module = value("--umbrella-module", in: rest)
    if sourceDirectory.isEmpty || outputDirectory.isEmpty || module.isEmpty {
        fail(
            "symbol-graph-umbrella requires --symbol-graph-dir, --umbrella-module"
                + " and --output-dir")
    }
    var excluded: Set<String> = []
    for (index, argument) in rest.enumerated() where argument == "--exclude-module" {
        if index + 1 < rest.count { excluded.insert(rest[index + 1]) }
    }
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: sourceDirectory)
    else {
        fail("symbol-graph-umbrella: \(sourceDirectory) is not a directory")
    }
    var pool: [CI.SymbolGraph.Graph] = []
    for name in CI.SymbolGraph.Umbrella.graphFiles(in: names) {
        guard let data = FileManager.default.contents(atPath: sourceDirectory + "/" + name),
              let graph = try? CI.SymbolGraph.Graph(
                name: name, text: String(decoding: data, as: UTF8.self))
        else { fail("symbol-graph-umbrella: \(name) is not a readable symbol graph") }
        pool.append(graph)
    }
    let umbrella = CI.SymbolGraph.Umbrella(module: module, excludedModules: excluded)
    let isolation: CI.SymbolGraph.Umbrella.Isolation
    do throws(CI.SymbolGraph.Umbrella.Error) {
        isolation = try umbrella.isolate(from: pool)
    } catch {
        FileHandle.standardError.write(
            Data("institute-ci: symbol-graph-umbrella refused: \(error)\n".utf8))
        exit(2)
    }
    try? FileManager.default.createDirectory(
        atPath: outputDirectory, withIntermediateDirectories: true)
    // Stale graphs from a prior run are removed, not merged over: the
    // isolation is the point of the directory.
    for stale in (try? FileManager.default.contentsOfDirectory(atPath: outputDirectory)) ?? []
    where stale.hasSuffix(".symbols.json") {
        try? FileManager.default.removeItem(atPath: outputDirectory + "/" + stale)
    }
    for graph in isolation.graphs {
        guard let text = try? graph.document.text(),
              (try? text.write(
                toFile: outputDirectory + "/" + graph.name,
                atomically: true, encoding: .utf8)) != nil
        else { fail("symbol-graph-umbrella: cannot write \(graph.name)") }
    }
    print(isolation.summary(outputDirectory: outputDirectory))

default:
    fail(
        "usage: institute-ci plan|aggregate|validate|validate-fixtures|workflow-json"
            + "|symbol-graph-umbrella"
            + "|bootstrap-identity|bootstrap-manifest|bootstrap-verify ...")
}
