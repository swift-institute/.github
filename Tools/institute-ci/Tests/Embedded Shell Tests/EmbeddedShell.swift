import CI_Contract
import CI_Workflow
import Foundation

/// A `run:` body extracted from a shipped workflow or composite action,
/// and run under a synthetic Actions environment.
///
/// The subject is the shipped bytes, extracted by name — not a copy kept
/// beside the test. That is the whole design of the two Python suites
/// this replaces, and the reason extraction *refuses* rather than
/// returning empty: a suite that silently tests nothing after a step is
/// renamed is worse than no suite, because it reports green.
struct EmbeddedShell {
    let script: String

    enum ExtractionFailure: Error, CustomStringConvertible {
        case unreadable(String)
        case malformed(String, String)
        case noJob(String, String)
        case noStep(String, String)
        case noBody(String, String)

        var description: String {
            switch self {
            case .unreadable(let file): "\(file): unreadable"
            case .malformed(let file, let message): "\(file): \(message)"
            case .noJob(let file, let job):
                "\(file): no job '\(job)' — extraction target gone"
            case .noStep(let file, let step):
                "\(file): no step named '\(step)'. This suite tests the shipped "
                    + "bytes by name; rename it here too."
            case .noBody(let file, let step): "\(file): step '\(step)' has no run: body"
            }
        }
    }

    /// The repository root, from this file's own location.
    static let repositoryRoot: String = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.path
    }()

    static func document(at path: String) throws -> CI.Workflow.Document {
        let full = repositoryRoot + "/" + path
        guard let data = FileManager.default.contents(atPath: full) else {
            throw ExtractionFailure.unreadable(path)
        }
        do throws(CI.Workflow.YAML.Error) {
            return try CI.Workflow.Document(
                name: path, text: String(decoding: data, as: UTF8.self))
        } catch {
            throw ExtractionFailure.malformed(path, error.message)
        }
    }

    /// The `run:` body of a named step of a named workflow job.
    static func workflowStep(
        _ path: String, job jobName: String, step stepName: String
    ) throws -> EmbeddedShell {
        let document = try document(at: path)
        guard let job = document.jobs.first(where: { $0.name == jobName }) else {
            throw ExtractionFailure.noJob(path, jobName)
        }
        return try shell(in: job.steps, named: stepName, of: path)
    }

    /// The `run:` body of a named step of a composite action.
    static func actionStep(_ path: String, step stepName: String) throws -> EmbeddedShell {
        let document = try document(at: path)
        let steps = document.body?["runs"]?.mapping?["steps"]?.sequence?
            .compactMap(\.mapping) ?? []
        return try shell(in: steps, named: stepName, of: path)
    }

    private static func shell(
        in steps: [CI.Workflow.YAML.Mapping], named stepName: String, of path: String
    ) throws -> EmbeddedShell {
        for step in steps where step["name"]?.text == stepName {
            guard let body = step["run"]?.text, !body.isEmpty else {
                throw ExtractionFailure.noBody(path, stepName)
            }
            return EmbeddedShell(script: body)
        }
        throw ExtractionFailure.noStep(path, stepName)
    }

    struct Result {
        let status: Int32
        let log: String
        let outputs: [String: String]
        let summary: String
    }

    /// Run the extracted body with a synthetic Actions environment.
    ///
    /// `preamble`, when given, is sourced through `BASH_ENV` — the shim
    /// channel the retired suites used to stand in for `gh`, `git`,
    /// `swift` and `swift-linter` without a network, a token or a
    /// toolchain.
    func run(
        environment additions: [String: String] = [:],
        preamble: String? = nil,
        path prefix: String? = nil,
        in directory: URL? = nil
    ) throws -> Result {
        let root = directory ?? URL(
            fileURLWithPath: NSTemporaryDirectory()
                + "embedded-shell-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        defer { if directory == nil { try? FileManager.default.removeItem(at: root) } }

        let script = root.appendingPathComponent("step.sh")
        try self.script.write(to: script, atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("github_output")
        let summary = root.appendingPathComponent("github_summary")
        FileManager.default.createFile(atPath: output.path, contents: Data())
        FileManager.default.createFile(atPath: summary.path, contents: Data())

        var environment = ProcessInfo.processInfo.environment
        environment["GITHUB_OUTPUT"] = output.path
        environment["GITHUB_STEP_SUMMARY"] = summary.path
        environment["GITHUB_REF"] = "refs/heads/feature"
        environment["GITHUB_SHA"] = String(repeating: "0", count: 40)
        // Since #276 task 1-03 every harness needs a lint bundle, even
        // where its own case does not vary one.
        environment["LINT_BUNDLE"] = "institute"
        if let preamble {
            let file = root.appendingPathComponent("preamble.bash")
            try preamble.write(to: file, atomically: true, encoding: .utf8)
            environment["BASH_ENV"] = file.path
        }
        if let prefix {
            environment["PATH"] = prefix + ":" + (environment["PATH"] ?? "")
        }
        environment.merge(additions) { _, new in new }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.currentDirectoryURL = root
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var outputs: [String: String] = [:]
        let recorded = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        for line in recorded.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            outputs[String(line[line.startIndex..<separator])] =
                String(line[line.index(after: separator)...])
        }
        return Result(
            status: process.terminationStatus,
            log: String(decoding: data, as: UTF8.self),
            outputs: outputs,
            summary: (try? String(contentsOf: summary, encoding: .utf8)) ?? "")
    }
}
