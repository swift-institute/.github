// Thin CLI mapping only; owns no predicate (annex: Institute CI Command).
import Byte_Primitives
import CI_Canon
import CI_Contract
import CI_Inventory
import CI_Symbol_Graph
import CI_Validation
import CI_Workflow
import Foundation
import Institute_CI_Application
import Institute_Receipt
import Rulebook

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
        let nightlyException = CI.Contract.NightlyException(
            image: value("--nightly-main-image", in: rest),
            upstreamIssue: value("--nightly-main-upstream-issue", in: rest),
            recheck: value("--nightly-main-recheck", in: rest))
        try nightlyException.validate(today: value("--today", in: rest))
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
    // The three-file face GH-REPO-063 inherited from its retired
    // script's positional arguments: the fixture corpus keeps the
    // schema, the sync workflow, and the readme consumer flat in one
    // scenario directory, so its caller names them rather than relying
    // on the subject-root defaults.
    let schemaFile = value("--schema", in: rest)
    let syncWorkflowFile = value("--sync-workflow", in: rest)
    let readmeValidatorFile = value("--readme-validator", in: rest)
    if !schemaFile.isEmpty || !syncWorkflowFile.isEmpty || !readmeValidatorFile.isEmpty {
        guard validator is CI.Validation.SchemaCorrespondence else {
            fail("validate: --schema/--sync-workflow/--readme-validator are not inputs to this validator")
        }
        validator = CI.Validation.SchemaCorrespondence(
            schemaFile: schemaFile.isEmpty ? nil : schemaFile,
            syncWorkflowFile: syncWorkflowFile.isEmpty ? nil : syncWorkflowFile,
            readmeValidatorFile: readmeValidatorFile.isEmpty ? nil : readmeValidatorFile)
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

case "verdict-inventory":
    // The structural inventory of the shipped verdict, as canonical
    // JSON. Regenerates the committed expectation corpus; the drift
    // check itself is a test, not a mode of this command, so that a
    // stale corpus fails the package rather than one workflow step.
    let rest = Array(arguments.dropFirst())
    let path = value("--universal", in: rest)
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("verdict-inventory: unreadable universal workflow \(path)")
    }
    do throws(CI.Inventory.Error) {
        let inventory = try CI.Inventory.Document(
            universalWorkflow: String(decoding: data, as: UTF8.self))
        print(inventory.canonicalJSON)
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
    let corpus = Rulebook.Corpus.read(roots: roots, files: files)
    guard !corpus.documents.isEmpty else {
        // Exit 2, not a clean report. A run that found no corpus has
        // measured nothing, and reporting zero findings would be the
        // silent no-op every gate in this repository exists to prevent.
        FileHandle.standardError.write(Data("::error::check-canon: no corpus files found\n".utf8))
        exit(2)
    }
    let configuration = value("--configuration", in: rest).isEmpty
        ? ".github/scripts" : value("--configuration", in: rest)
    let audit = Rulebook.Audit(
        corpus: corpus,
        baseline: .read(at: "\(configuration)/.check-canon-baseline"),
        allowlist: .read(at: "\(configuration)/.check-canon-allowlist"),
        developerRoot: developerRoot)
    let selected = values("--check", in: rest).compactMap(Rulebook.Check.init(rawValue:))
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
    do throws(Rulebook.Census.Error) {
        let census = try Rulebook.Census.taken(over: roots)
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

case "render-gitignore":
    // The propagation face — the Swift owner of
    // `.github/scripts/render-gitignore.py`, driven by
    // `sync-gitignore.yml`. Writes the rendered file to stdout with no
    // terminator of its own; the caller byte-compares it against the
    // target, so a conformant repository produces no commit.
    let rest = Array(arguments.dropFirst())
    let canonPath = value("--canon", in: rest)
    let targetPath = value("--target", in: rest)
    if canonPath.isEmpty {
        fail("render-gitignore requires --canon <path> [--target <path>]")
    }
    guard let canonData = FileManager.default.contents(atPath: canonPath) else {
        fail("render-gitignore: canon not found: \(canonPath)")
    }
    let existing = FileManager.default.contents(atPath: targetPath)
        .map { CI.Canon.Gitignore(String(decoding: $0, as: UTF8.self)) }
    do throws(CI.Canon.Gitignore.Render.Error) {
        let render = try CI.Canon.Gitignore.Render(
            canon: .init(String(decoding: canonData, as: UTF8.self)))
        FileHandle.standardOutput.write(Data(render(over: existing).utf8))
    } catch {
        fail("\(error.message): \(canonPath)")
    }

case "runtime-receipt":
    // The pure base canonicalizer (TX7 §8.9; P19/P20). Reads the run
    // object and jobs collection the aggregate fetched for its OWN run;
    // it never calls GitHub and never claims a terminal conclusion.
    let rest = Array(arguments.dropFirst())
    let output = value("--output", in: rest)
    guard let runData = FileManager.default.contents(atPath: value("--run-json", in: rest)),
          let jobsData = FileManager.default.contents(atPath: value("--jobs-json", in: rest))
    else { fail("runtime-receipt: --run-json and --jobs-json must both be readable") }
    let attestation: Institute.Receipt.Attestation
    do throws(Institute.Receipt.Capture.Error) {
        attestation = try Institute.Receipt.Capture.attestation(
            runJSON: [UInt8](runData).map(Byte.init),
            jobsJSON: [UInt8](jobsData).map(Byte.init),
            plannedGating: value("--planned-gating", in: rest)
                .split(separator: ",").map(String.init),
            subjectRepository: value("--subject-repository", in: rest),
            subjectSha: value("--subject-sha", in: rest),
            subjectVisibility: value("--subject-visibility", in: rest))
    } catch {
        FileHandle.standardError.write(Data("::error::\(error)\n".utf8))
        exit(1)
    }
    let payload = Institute.Receipt.Canonical.bytes(of: attestation)
    let digest = Institute.Receipt.Canonical.digest(of: payload)
    let bytes = Data(payload.map(\.underlying))
    guard FileManager.default.createFile(atPath: output, contents: bytes),
          FileManager.default.createFile(
            atPath: output + ".sha256", contents: Data((digest + "\n").utf8))
    else { fail("runtime-receipt: could not write \(output)") }
    print("effective-runtime-receipt-base-digest=\(digest)")
    print("effective-runtime-receipt-stage=\(attestation.stage.rawValue)")
    if attestation.verdict == .unmeasured {
        FileHandle.standardError.write(
            Data("::error::referenced_workflows is empty/unavailable — the reusable-workflow chain is UNMEASURED and this aggregate must fail (P20).\n".utf8))
        exit(1)
    }

case "startup-failures":
    // The weekly probe's predicate. Input is a runs payload on a path
    // or on stdin; exit 1 means at least one run never started.
    let rest = Array(arguments.dropFirst())
    let path = rest.first { !$0.hasPrefix("-") } ?? "-"
    let data: Data
    if path == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
    } else if let contents = FileManager.default.contents(atPath: path) {
        data = contents
    } else {
        FileHandle.standardError.write(Data("# error: cannot read \(path)\n".utf8))
        exit(2)
    }
    let probe: Institute.Receipt.Run.Startup
    do throws(Institute.Receipt.Run.Summary.Error) {
        probe = .init(
            scanning: try Institute.Receipt.Run.Summary.collection(
                [UInt8](data).map(Byte.init)))
    } catch {
        FileHandle.standardError.write(Data("# error: \(error)\n".utf8))
        exit(2)
    }
    if probe.isClean {
        print("clean: 0 startup_failure runs in \(probe.inspected.count) recent run(s).")
        exit(0)
    }
    print(
        "FLAGGED: \(probe.flagged.count) startup_failure run(s) in "
            + "\(probe.inspected.count) recent run(s):")
    for run in probe.flagged {
        let line = "  - \(run.name ?? "?") (run \(run.id.map(String.init) ?? "?")) "
            + (run.htmlURL ?? "")
        print(String(line.reversed().drop { $0 == " " }.reversed()))
    }
    exit(1)

case "runtime-receipt-augment":
    // The post-completion collector. Credentialed by construction: it
    // reads the completed run and its complete paginated jobs
    // collection, so unlike every other face here it cannot be measured
    // against a static corpus — its predicate is `Augmentation.outcome`,
    // which is measured, and this face is the transport around it.
    let rest = Array(arguments.dropFirst())
    let repository = value("--repo", in: rest)
    let runIdentifier = value("--run-id", in: rest)
    guard let attempt = Int(value("--attempt", in: rest)) else {
        fail("runtime-receipt-augment: --attempt must be an integer")
    }

    func api(_ path: String) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "api", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        // say gh is unavailable, which is what this does.
        // swift-linter:disable:next try optional
        // REASON: Process.run() throws untyped; the only recovery is to report gh unavailable, which is what this does.
        guard (try? process.run()) != nil else { fail("gh is not available") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 { fail("gh api \(path) failed") }
        return data
    }

    func object(_ data: Data) -> [String: Any] {
        // unreadable response and an empty one are handled identically
        // downstream, by the refusals in Augmentation.
        // swift-linter:disable:next try optional
        // REASON: JSONSerialization.jsonObject throws untyped; an unreadable response and an empty one are refused identically downstream, by Augmentation.
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // The base artifact: exactly one, by name. A sweep run carries one
    // receipt per swept subject, so "more than one" is ambiguity, not a
    // convenience to resolve by picking the first.
    let artifactName = value("--base-artifact", in: rest)
    let artifacts = object(
        api("repos/\(repository)/actions/runs/\(runIdentifier)/artifacts?per_page=100"))
    let matches = (artifacts["artifacts"] as? [[String: Any]] ?? [])
        .filter { $0["name"] as? String == artifactName }
    guard matches.count == 1, let artifactIdentifier = matches[0]["id"] as? Int else {
        fail("expected exactly one artifact named \(artifactName), found \(matches.count)")
    }
    let archive = FileManager.default.temporaryDirectory
        .appendingPathComponent("receipt-\(artifactIdentifier).zip")
    // the empty-extraction refusal two statements below.
    // swift-linter:disable:next try optional
    // REASON: Data.write(to:) throws untyped; a failed write surfaces as the empty-extraction refusal below.
    try? api("repos/\(repository)/actions/artifacts/\(artifactIdentifier)/zip")
        .write(to: archive)
    let extraction = Process()
    extraction.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    extraction.arguments = ["unzip", "-p", archive.path, "*.base.json"]
    let extracted = Pipe()
    extraction.standardOutput = extracted
    // swift-linter:disable:next try optional
    // REASON: Process.run() throws untyped.
    guard (try? extraction.run()) != nil else { fail("unzip is not available") }
    let baseData = extracted.fileHandleForReading.readDataToEndOfFile()
    extraction.waitUntilExit()
    guard extraction.terminationStatus == 0, !baseData.isEmpty else {
        fail("the base artifact carries no .base.json")
    }

    let basePayload = [UInt8](baseData).map(Byte.init)
    let baseDigest = Institute.Receipt.Canonical.digest(of: basePayload)
    let base: Institute.Receipt.Attestation
    do throws(Institute.Receipt.Canonical.Error) {
        base = try Institute.Receipt.Canonical.attestation(from: basePayload)
    } catch {
        FileHandle.standardError.write(Data("::error::\(error)\n".utf8))
        exit(1)
    }

    let liveRun = object(api("repos/\(repository)/actions/runs/\(runIdentifier)"))
    var conclusions: [Int: Institute.Receipt.Conclusion?] = [:]
    var page = 1
    while true {
        let document = object(
            api("repos/\(repository)/actions/runs/\(runIdentifier)/jobs?per_page=100&page=\(page)"))
        let rows = document["jobs"] as? [[String: Any]] ?? []
        for row in rows {
            guard let identifier = row["id"] as? Int else { continue }
            conclusions[identifier] =
                (row["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) }
        }
        if rows.count < 100 { break }
        page += 1
    }

    let outcome: Institute.Receipt.Augmentation.Outcome
    do throws(Institute.Receipt.Augmentation.Refusal) {
        outcome = try Institute.Receipt.Augmentation.outcome(
            base: base,
            baseReceiptDigest: baseDigest,
            run: .init(
                id: liveRun["id"] as? Int,
                attempt: liveRun["run_attempt"] as? Int,
                headSha: liveRun["head_sha"] as? String,
                event: liveRun["event"] as? String,
                conclusion: (liveRun["conclusion"] as? String).map { Institute.Receipt.Conclusion($0) },
                repository: (liveRun["repository"] as? [String: Any])?["full_name"] as? String,
                workflowPath: liveRun["path"] as? String),
            status: liveRun["status"] as? String ?? "",
            attempt: attempt,
            conclusions: conclusions)
    } catch {
        FileHandle.standardError.write(Data("::error::\(error)\n".utf8))
        exit(1)
    }

    let output = value("--output", in: rest)
    // directory is the common case and a genuine failure surfaces as the
    // createFile refusal below.
    // swift-linter:disable:next try optional
    // REASON: FileManager.createDirectory throws untyped; an existing directory is the common case and a real failure surfaces as the createFile refusal below.
    try? FileManager.default.createDirectory(
        atPath: (output as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
    let terminalPayload = Institute.Receipt.Canonical.bytes(of: outcome.attestation)
    guard FileManager.default.createFile(
        atPath: output, contents: Data(terminalPayload.map(\.underlying)))
    else { fail("runtime-receipt-augment: could not write \(output)") }
    for job in outcome.mandatoryFailures {
        FileHandle.standardError.write(
            Data("::warning::mandatory selected job '\(job.name)' concluded '\(job.conclusion?.rawValue ?? "null")'\n".utf8))
    }
    print("terminal-receipt-digest=\(Institute.Receipt.Canonical.digest(of: terminalPayload))")
    print("terminal-verdict=\(outcome.attestation.verdict.rawValue)")
    exit(outcome.attestation.verdict == .met ? 0 : 1)

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
    let umbrella = CI.SymbolGraph.Umbrella(module: module, excludedModules: excluded)
    let isolation: CI.SymbolGraph.Umbrella.Isolation
    do throws(CI.SymbolGraph.Umbrella.Error) {
        isolation = try umbrella.isolate(files: names) { name in
            guard let data = FileManager.default.contents(
                atPath: sourceDirectory + "/" + name)
            else { return nil }
            do throws(CI.SymbolGraph.JSON.Error) {
                return try CI.SymbolGraph.Graph(
                    name: name, text: String(decoding: data, as: UTF8.self))
            } catch {
                return nil
            }
        }
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
            + "|verdict-inventory|render-gitignore|symbol-graph-umbrella"
            + "|bootstrap-identity|bootstrap-manifest|bootstrap-verify"
            + "|runtime-receipt|runtime-receipt-augment|startup-failures ...")
}
