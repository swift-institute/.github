import Fleet_Audit
import Foundation

extension Institute.CI.Control.Application {
    /// The credentialed edge of the cron sweep: list an org, clone each
    /// public target, run one audit over the clone, hand the report to
    /// `Fleet.Audit.Sweep`, and write the artefacts.
    ///
    /// Everything credentialed is here, and nothing else is. The
    /// accumulation, the per-package rendering and the summary are
    /// `Fleet Audit`'s and are proved there without a token; this shell
    /// is proved by the hosted dry-run canary, which is the only place
    /// an App token is real.
    public enum Audit {
        /// Which audit runs over each clone.
        public enum Kind: Sendable, Equatable {
            /// The γ-2 mechanical-hygiene audit, in Swift.
            case mechanicalHygiene
            /// A Python audit script, invoked over the clone exactly as
            /// the retired runner invoked it. Retained for the two
            /// callers whose audits are swift-linter's to port (the CW
            /// cross-programme hold), and no longer than that.
            case script(path: String)

            public init(name: String) {
                switch name {
                case "mechanical-hygiene": self = .mechanicalHygiene
                default: self = .script(path: name)
                }
            }
        }

        public enum Error: Swift.Error, Equatable {
            case missingToken
            case organizationUnreadable(String)
            case configuration(Fleet.Audit.Configuration.Error)
            case rendering(Fleet.Audit.Sweep.Error)
        }

        /// Run one org's sweep. `dryRun` lists and audits nothing,
        /// reporting the targets the sweep would visit — the shape the
        /// canary is dispatched in.
        public static func sweep(
            organization: String,
            configuration: Fleet.Audit.Configuration,
            kind: Kind,
            token: String,
            artefactDirectory: String,
            summaryPath: String?,
            dryRun: Bool
        ) throws(Error) -> Fleet.Audit.Sweep.Outcome {
            if token.isEmpty { throw .missingToken }
            let sweep = Fleet.Audit.Sweep(
                organization: organization, configuration: configuration)

            guard let targets = publicTargets(organization: organization, token: token) else {
                throw .organizationUnreadable(organization)
            }

            var reports: [(package: String, report: Fleet.Audit.Report)] = []
            if !dryRun {
                for target in targets {
                    guard let clone = clone(target, token: token) else { continue }
                    defer { try? FileManager.default.removeItem(atPath: clone) }
                    let package = String(target.split(separator: "/").last ?? "")
                    reports.append(
                        (package, report(of: clone, package: package, kind: kind,
                                         keys: configuration.countKeys,
                                         totalsPath: configuration.totalsPath)))
                }
            }

            let outcome: Fleet.Audit.Sweep.Outcome
            do throws(Fleet.Audit.Sweep.Error) {
                outcome = try sweep.accumulate(reports)
            } catch { throw .rendering(error) }

            write(
                outcome, organization: organization, configuration: configuration,
                directory: artefactDirectory, summaryPath: summaryPath,
                targetCount: targets.count, dryRun: dryRun)
            return outcome
        }

        // MARK: - The credentialed calls

        static func publicTargets(organization: String, token: String) -> [String]? {
            let listing = run(
                ["gh", "repo", "list", organization, "--limit", "2000",
                 "--visibility", "public",
                 "--json", "nameWithOwner,isArchived",
                 "--jq", ".[] | select(.isArchived==false) | .nameWithOwner"],
                environment: ["GH_TOKEN": token])
            guard listing.status == 0 else { return nil }
            return listing.standardOutput
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        static func clone(_ target: String, token: String) -> String? {
            let directory = NSTemporaryDirectory()
                + "cron-audit-" + target.replacingOccurrences(of: "/", with: "__")
            try? FileManager.default.removeItem(atPath: directory)
            let url = "https://x-access-token:\(token)@github.com/\(target).git"
            let cloned = run(["git", "clone", "--depth", "1", "--quiet", url, directory])
            return cloned.status == 0 ? directory : nil
        }

        // MARK: - The audit over one clone

        public static func report(
            of clone: String, package: String, kind: Kind,
            keys: [String], totalsPath: String
        ) -> Fleet.Audit.Report {
            switch kind {
            case .mechanicalHygiene:
                return mechanicalHygiene(of: clone, package: package)
            case .script(let path):
                let output = NSTemporaryDirectory() + package + ".audit.json"
                _ = run(["python3", path, "--package-dir", clone, "--json", output])
                let text = (try? String(contentsOfFile: output, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(atPath: output)
                return Fleet.Audit.Report(
                    package: package,
                    counters: Fleet.Audit.Report.counters(
                        inJSON: text, at: totalsPath, keys: keys))
            }
        }

        static func mechanicalHygiene(
            of clone: String, package: String
        ) -> Fleet.Audit.Report {
            let manager = FileManager.default
            let subjects = Fleet.Audit.MechanicalHygiene.present(in: clone) { path, wantsDirectory in
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                    return false
                }
                return isDirectory.boolValue == wantsDirectory
            }
            var issues = 0
            if !subjects.isEmpty,
               manager.fileExists(atPath: Fleet.Audit.Yamllint.configurationPath) {
                let linted = run(Fleet.Audit.Yamllint.invocation(subjects: subjects))
                issues = Fleet.Audit.MechanicalHygiene.yamlIssueCount(
                    inTranscript: linted.standardOutput)
            }
            return Fleet.Audit.MechanicalHygiene.report(
                package: package, yamlIssues: issues,
                brokenLinks: brokenLinkCount(under: clone))
        }

        static func brokenLinkCount(under root: String) -> Int {
            let manager = FileManager.default
            guard let walk = manager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []) else { return 0 }
            var entries: [(path: String, isSymlink: Bool, resolves: Bool)] = []
            for case let url as URL in walk {
                let attributes = try? manager.attributesOfItem(atPath: url.path)
                let isSymlink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
                guard isSymlink else { continue }
                entries.append(
                    (url.path, true, manager.fileExists(atPath: url.resolvingSymlinksInPath().path)))
            }
            return Fleet.Audit.MechanicalHygiene.brokenLinkCount(among: entries)
        }

        // MARK: - Artefacts

        static func write(
            _ outcome: Fleet.Audit.Sweep.Outcome,
            organization: String,
            configuration: Fleet.Audit.Configuration,
            directory: String,
            summaryPath: String?,
            targetCount: Int,
            dryRun: Bool
        ) {
            let counts = outcome.countsArtefact(keys: configuration.countKeys)
            try? counts.write(
                toFile: directory + "/\(organization)-counts.txt",
                atomically: true, encoding: .utf8)
            if let extra = outcome.extraArtefact {
                try? extra.write(
                    toFile: directory + "/\(organization)-extra.txt",
                    atomically: true, encoding: .utf8)
            }
            guard let summaryPath else { return }
            var summary = outcome.summary(
                organization: organization,
                label: configuration.summaryLabel,
                keys: configuration.countKeys)
            if dryRun {
                summary += "- dry run: \(targetCount) target(s) would have been audited\n"
            }
            // Appended, and created when absent: a summary that silently
            // wrote nowhere would be indistinguishable from a sweep that
            // found nothing.
            if !FileManager.default.fileExists(atPath: summaryPath) {
                FileManager.default.createFile(atPath: summaryPath, contents: nil)
            }
            let handle = FileHandle(forWritingAtPath: summaryPath)
            handle?.seekToEndOfFile()
            handle?.write(Data(summary.utf8))
            try? handle?.close()
        }

        // MARK: - Process

        public struct Completion: Sendable {
            public let status: Int32
            public let standardOutput: String
        }

        /// Argument-vector execution only. There is no shell here and no
        /// caller-supplied command: the structured-input contract
        /// ([CI-081]) that closed the template-injection class on this
        /// App-token-holding job is a property of this function.
        @discardableResult
        public static func run(
            _ arguments: [String], environment additions: [String: String] = [:]
        ) -> Completion {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
            if !additions.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(
                    additions) { _, new in new }
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return Completion(status: 127, standardOutput: "")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Completion(
                status: process.terminationStatus,
                standardOutput: String(decoding: data, as: UTF8.self))
        }
    }
}
