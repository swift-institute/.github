// Thin CLI mapping only; owns no predicate (annex: Institute CI Control
// Command). Verbs arrive with their activation waves (F13/F14).
import Fleet_Audit
import Foundation
import GitHub
import GitHub_Control
import Institute_CI_Control_Application

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("institute-ci-control: \(message)\n".utf8))
    exit(2)
}

func value(_ flag: String, in arguments: [String]) -> String {
    guard let index = arguments.firstIndex(of: flag),
          index + 1 < arguments.count else { return "" }
    return arguments[index + 1]
}

func environment(_ name: String) -> String {
    ProcessInfo.processInfo.environment[name] ?? ""
}

switch arguments.first {
case "audit-setup":
    // One-time per-matrix-job setup, before the sweep's target loop.
    let rest = Array(arguments.dropFirst())
    switch Institute.CI.Control.Application.Audit.Kind(name: value("--audit", in: rest)) {
    case .mechanicalHygiene:
        let installed = Institute.CI.Control.Application.Audit.run(
            Fleet.Audit.Yamllint.installation)
        if installed.status != 0 { fail("audit-setup: yamllint installation failed") }
        do {
            try Fleet.Audit.Yamllint.configuration.write(
                toFile: Fleet.Audit.Yamllint.configurationPath,
                atomically: true, encoding: .utf8)
        } catch {
            fail("audit-setup: cannot write \(Fleet.Audit.Yamllint.configurationPath)")
        }
    case .script:
        // An audit whose setup is still Python (CW hold) supplies its
        // own setup step; there is nothing for this verb to do.
        break
    }

case "audit":
    // One audit over one already-obtained package directory — the face
    // the retired per-package audit scripts had, kept because it is the
    // face the sweep's audit can be measured through without a token.
    let rest = Array(arguments.dropFirst())
    let directory = value("--package-dir", in: rest)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        fail("audit: \(directory) is not a directory")
    }
    let resolved = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
        .path
    let report = Institute.CI.Control.Application.Audit.report(
        of: resolved,
        package: (resolved as NSString).lastPathComponent,
        kind: .init(name: value("--audit", in: rest)),
        keys: [], totalsPath: "totals")
    let rendered = report.json(directory: resolved)
    let output = value("--json", in: rest)
    if output.isEmpty {
        print(rendered)
    } else {
        do {
            try rendered.write(toFile: output, atomically: true, encoding: .utf8)
        } catch {
            fail("audit: cannot write \(output)")
        }
    }

case "cron-audit":
    // The per-target sweep face, replacing `python3 cron-audit-runner.py
    // --audit-script … --org … --args-json …`. Configuration still
    // arrives as one JSON document over an env channel: the structured-
    // input contract ([CI-081]) is the reason it is a document and not a
    // shell string, and that has not changed.
    let rest = Array(arguments.dropFirst())
    let configuration: Fleet.Audit.Configuration
    do throws(Fleet.Audit.Configuration.Error) {
        configuration = try .init(json: environment("AUDIT_RUNNER_ARGS"))
    } catch {
        fail("cron-audit: AUDIT_RUNNER_ARGS refused: \(error)")
    }
    let organization = value("--org", in: rest)
    if organization.isEmpty { fail("cron-audit requires --org <organization>") }
    let summary = environment("GITHUB_STEP_SUMMARY")
    do throws(Institute.CI.Control.Application.Audit.Error) {
        let outcome = try Institute.CI.Control.Application.Audit.sweep(
            organization: organization,
            configuration: configuration,
            kind: .init(name: value("--audit", in: rest)),
            token: environment("GH_TOKEN"),
            artefactDirectory: value("--artefact-dir", in: rest).isEmpty
                ? "/tmp" : value("--artefact-dir", in: rest),
            summaryPath: summary.isEmpty ? nil : summary,
            dryRun: rest.contains("--dry-run"))
        print(outcome.countsArtefact(keys: configuration.countKeys), terminator: "")
    } catch {
        fail("cron-audit: \(error)")
    }

case "dependency-snapshot":
    // `swift package show-dependencies --format json` → the document
    // `POST /repos/<owner>/<repo>/dependency-graph/snapshots` takes.
    // Submission stays the caller's; this verb holds no credential.
    let rest = Array(arguments.dropFirst())
    let path = value("--dependencies", in: rest)
    guard let data = FileManager.default.contents(atPath: path),
          let tree = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
        fail("dependency-snapshot: cannot read a dependency tree at '\(path)'")
    }
    let sha = environment("GITHUB_SHA")
    if sha.isEmpty { fail("dependency-snapshot: GITHUB_SHA is required") }
    let reference = environment("GITHUB_REF")
    let snapshot = GitHub.Control.DependencySnapshot(
        sha: sha,
        ref: reference.isEmpty ? "refs/heads/main" : reference,
        job: .init(
            id: environment("GITHUB_RUN_ID").isEmpty ? "0" : environment("GITHUB_RUN_ID"),
            correlator: environment("GITHUB_RUN_NUMBER").isEmpty
                ? "swift-institute-bot" : environment("GITHUB_RUN_NUMBER")),
        scanned: GitHub.Control.DependencySnapshot.scanned(Date()),
        resolutions: GitHub.Control.DependencySnapshot.resolutions(ofDependencyTree: tree))
    guard let json = try? snapshot.json() else {
        fail("dependency-snapshot: snapshot is not serialisable")
    }
    print(json)

default:
    fail("usage: institute-ci-control audit|audit-setup|cron-audit|dependency-snapshot ...")
}
