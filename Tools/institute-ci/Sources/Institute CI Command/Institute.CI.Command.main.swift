// Thin CLI mapping only; owns no predicate (annex: Institute CI Command).
import Byte_Primitives
import CI_Contract
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
default:
    fail("usage: institute-ci plan|aggregate|bootstrap-identity|bootstrap-manifest|bootstrap-verify ...")
}
