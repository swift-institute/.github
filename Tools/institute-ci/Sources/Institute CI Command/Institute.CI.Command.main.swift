// Thin CLI mapping only; owns no predicate (annex: Institute CI Command).
import Byte_Primitives
import CI_Contract
import CI_Validation
import CI_Workflow
import Foundation
import Institute_CI_Application
import Institute_Receipt

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("institute-ci: \(message)\n".utf8))
    exit(2)
}

/// `validate --script` found no Swift owner for that retired script.
///
/// A third code, distinct from `0` (ran) and `2` (could not run),
/// because during the port "this file has not been ported yet" is a
/// normal, expected answer and must not be readable as either a clean
/// scan or a broken machine. `validate-base.yml` reads exactly this
/// code as "serve this target with python3".
let unportedScript: Int32 = 3

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
    //
    // Two ways to name the validator, because two callers ask
    // differently. A person, a test, or the harness names a **rule**.
    // `validate-base.yml` names the **retired script** — that is what
    // its fifty callers declare — and needs an answer for a script that
    // has no Swift owner yet, which is the transition window's whole
    // shape. So `--script` on an unported script is not a failure: it
    // exits `unportedScript` (3), distinct from both `0` (ran) and `2`
    // (could not run), and the scan loop reads that one code as "fall
    // back to python3".
    let rest = Array(arguments.dropFirst())
    let script = value("--script", in: rest)
    var validator: any CI.Validation.Validator
    if script.isEmpty {
        let rule = CI.Validation.Rule(value("--rule", in: rest))
        guard let registered = CI.Validation.Registry.validator(for: rule) else {
            fail("validate: no Swift validator is registered for rule '\(rule)'")
        }
        validator = registered
    } else {
        guard let registered = CI.Validation.Registry.validator(replacing: script) else {
            exit(unportedScript)
        }
        validator = registered
    }
    // Support-file overrides. Only the validators that read a support
    // file consult these, and they are passed through rather than
    // discovered so a sweep over a foreign checkout can name the
    // manifest and the ledger it means — the shape the retired
    // `validate-branch-pins.py --orgs-file … --baseline …` invocation
    // already had.
    let organizationsFile = value("--orgs-file", in: rest)
    let baselineFile = value("--baseline", in: rest)
    if !organizationsFile.isEmpty || !baselineFile.isEmpty {
        guard validator is CI.Validation.BranchPins else {
            fail("validate: --orgs-file/--baseline are not inputs to this validator")
        }
        validator = CI.Validation.BranchPins(
            organizationsFile: organizationsFile.isEmpty ? nil : organizationsFile,
            baselineFile: baselineFile.isEmpty ? nil : baselineFile)
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

    // Transitional: every rule directory the registry does not own yet
    // is run through its retired script, so retiring `run.sh` does not
    // narrow the corpus gate while the port is in progress. `--scripts`
    // names the directory holding them; omitting it declines the
    // fallback, which is what the end state does.
    //
    // A directory that is neither owned by the registry nor covered by
    // the table is a hard failure, not a skip. `run.sh` failed the run
    // on exactly that condition, and it is the invariant worth keeping:
    // an unowned corpus is indistinguishable from a clean one.
    var residue = report.unownedRuleDirectories
    var fallbackFailures = 0
    var fallbackPassed = 0
    let scriptsDirectory = value("--scripts", in: rest)
    if !scriptsDirectory.isEmpty {
        var unresolved: [String] = []
        for directory in residue {
            let corpus = CI.Validation.Corpus(root: root)
            let scenarios: [CI.Validation.Corpus.Scenario]
            do throws(CI.Validation.EnvironmentDefect) {
                scenarios = try corpus.scenarios(in: directory)
            } catch {
                fail(error.message)
            }
            // A directory with no `pass/`, `fail/` or `edge/` scenarios
            // is shared fixture data, not a rule corpus — `fixtures/
            // callers/` and `fixtures/wrappers/` are read by other
            // suites. `run.sh` reached the same conclusion by never
            // dispatching them; here it is said rather than implied.
            if scenarios.isEmpty { continue }
            guard let script = Institute.CI.Application.RetiredValidator.scripts[directory] else {
                unresolved.append(directory)
                continue
            }
            let rule = Institute.CI.Application.RetiredValidator.rule(forDirectory: directory)
            for scenario in scenarios {
                let output = Institute.CI.Application.RetiredValidator.run(
                    script: "\(scriptsDirectory)/\(script)",
                    repository: scenario.repository, root: scenario.root)
                let found = output.split(separator: "\n").filter { line in
                    line.split(separator: "\t", omittingEmptySubsequences: false)
                        .dropFirst().first == rule[...]
                }
                let satisfied =
                    scenario.expectation == .violating ? !found.isEmpty : found.isEmpty
                if satisfied { fallbackPassed += 1 } else { fallbackFailures += 1 }
                print(
                    "  \(satisfied ? "PASS" : "FAIL") \(rule) (python3) "
                        + "\(scenario.expectation.rawValue)/\(scenario.name)"
                        + " (\(found.count) finding(s))")
            }
        }
        residue = unresolved
    }

    print("")
    print(
        "Total: \(report.satisfied.count + fallbackPassed) passed, "
            + "\(report.unsatisfied.count + fallbackFailures) failed")
    if !residue.isEmpty {
        // Named, not silently skipped. `run.sh` failed the run on any
        // unregistered rule directory; during the port that residue is
        // expected, so it is reported and gated by --require-complete.
        print(
            "Awaiting a Swift validator (\(residue.count)): "
                + residue.joined(separator: ", "))
    }
    // With the fallback armed a residue entry means *nothing* ran for
    // that rule — neither engine owns it — which is the condition
    // `run.sh` refused to pass. Without it, residue is the ordinary
    // in-progress state and only `--require-complete` gates on it.
    let unowned = scriptsDirectory.isEmpty
        ? (rest.contains("--require-complete") ? !residue.isEmpty : false)
        : !residue.isEmpty
    if !scriptsDirectory.isEmpty && !residue.isEmpty {
        FileHandle.standardError.write(
            Data(
                ("institute-ci: no engine owns \(residue.count) rule "
                    + "director(ies): \(residue.joined(separator: ", "))\n").utf8))
    }
    let failed = !report.isSatisfied || fallbackFailures > 0 || unowned
    exit(failed ? 1 : 0)

default:
    fail(
        "usage: institute-ci plan|aggregate|validate|validate-fixtures|workflow-json"
            + "|bootstrap-identity|bootstrap-manifest|bootstrap-verify ...")
}
