import CI_Contract
import CI_Workflow

extension CI.Validation {
    /// `[CI-010]` the universal CI matrix's shape, and `[CI-099]` the
    /// gating posture of `windows-release`.
    ///
    /// One validator for two rules because they are two readings of one
    /// file: the matrix must contain four named jobs on the right runner
    /// classes plus the advisory Apple-simulator leg (`CI-010`), and the
    /// Windows leg must stay gating (`CI-099`). Splitting them would mean
    /// two parses of the same document and two places for the job-name
    /// vocabulary to drift.
    ///
    /// The posture contrast is the point. `linux-nightly` *must* be
    /// advisory — a nightly toolchain's instability is noise. Windows
    /// *must not* be — it is a target the ecosystem ships to, and
    /// advisory-flipping it hides `#if os(Windows)` divergence and source
    /// incompatibilities. `apple-simulator-build` is advisory during its
    /// soak window but is never collapsed below the four Apple platforms:
    /// it exercises the resource-bundle CodeSign phase that
    /// `swift build` and `swift test` skip.
    ///
    /// Scope is the canonical universal reusable only. Layer wrappers
    /// host their own `swift-ci.yml` with intentionally different shapes,
    /// so the validator is silent unless the subject is
    /// `swift-institute/.github` or a test subject.
    ///
    /// The rule asserts the matrix jobs are present and well-shaped; it
    /// does not enumerate every job. Quality gates are `[CI-002]`'s.
    public struct CIMatrix: Validator {
        public let rules: [Rule] = ["CI-010", "CI-099"]
        public let retiredScript: String? = ".github/scripts/validate-ci-matrix.py"

        public init() {}

        /// The universal reusable's home. Any other subject is a layer
        /// wrapper or an unrelated repository.
        public static let canonicalRepository = "swift-institute/.github"

        /// The four gating legs, in the order findings cite them.
        static let requiredJobs: [(name: String, runner: String)] = [
            ("macos-release", "macos"),
            ("linux-release", "ubuntu"),
            ("linux-nightly", "ubuntu"),
            ("windows-release", "windows"),
        ]

        /// The Apple simulator platforms the advisory leg must cover.
        /// Never collapsed (M4 REJECT, 2026-05-06).
        static let applePlatforms: Set<String> = ["iOS", "tvOS", "watchOS", "visionOS"]

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let shape = rules[0]
            let posture = rules[1]

            // A test subject is in scope so the fixture corpus needs no
            // marker file; production reaches only the canonical repo.
            guard subject.repository == Self.canonicalRepository
                || subject.repository.contains("-test/")
            else { return [] }

            guard let text = try subject.text(at: ".github/workflows/swift-ci.yml") else {
                return []
            }
            let document: CI.Workflow.Document
            do {
                document = try CI.Workflow.Document(name: "swift-ci.yml", text: text)
            } catch {
                return [
                    Finding(
                        repository: subject.repository, rule: shape,
                        message: "YAML parse failed: \(error.message)")
                ]
            }
            guard document.body != nil else {
                return [
                    Finding(
                        repository: subject.repository, rule: shape,
                        message: "workflow YAML root is not a mapping")
                ]
            }
            guard let jobs = document.body?["jobs"]?.mapping else {
                return [
                    Finding(
                        repository: subject.repository, rule: shape,
                        message: "workflow has no jobs: block")
                ]
            }

            var findings: [Finding] = []
            func report(_ rule: Rule, _ message: String) {
                findings.append(
                    Finding(repository: subject.repository, rule: rule, message: message))
            }
            /// A job's body, or `nil` when the entry is absent or is not
            /// a mapping. A malformed entry is not a present job.
            func job(_ name: String) -> CI.Workflow.YAML.Mapping? { jobs[name]?.mapping }

            for required in Self.requiredJobs where jobs[required.name] == nil {
                report(
                    shape,
                    "required matrix job \(required.name.pythonQuoted) missing from "
                        + "jobs: block per [CI-010]")
            }
            for required in Self.requiredJobs {
                guard let body = job(required.name) else { continue }
                if let finding = Self.runnerFinding(
                    job: required.name, body: body, expecting: required.runner)
                {
                    report(shape, finding)
                }
            }
            if let nightly = job("linux-nightly"), nightly["continue-on-error"]?.boolean != true {
                report(shape, Self.nightlyMessage)
            }
            if let windows = job("windows-release"),
               windows["continue-on-error"]?.boolean == true
            {
                report(posture, Self.windowsMessage)
            }
            guard let apple = job("apple-simulator-build") else {
                report(shape, Self.missingAppleMessage)
                return findings
            }
            if let finding = Self.runnerFinding(
                job: "apple-simulator-build", body: apple, expecting: "macos")
            {
                report(shape, finding)
            }
            if apple["continue-on-error"]?.boolean != true {
                report(shape, Self.appleAdvisoryMessage)
            }
            let declared = apple["strategy"]?["matrix"]?["platform"]?.sequence ?? []
            let missing = Self.applePlatforms.subtracting(declared.compactMap(\.text))
            if !missing.isEmpty {
                report(shape, Self.collapsedMatrixMessage(missing: missing.sorted()))
            }
            return findings
        }

        /// The runner-class check: the declared `runs-on:` must mention
        /// the expected operating system, case-insensitively.
        ///
        /// A substring test rather than an equality test because the
        /// runner label carries a version (`macos-26`, `ubuntu-latest`)
        /// that the rule deliberately does not pin — pinning it here
        /// would make a runner-image bump read as a matrix defect.
        static func runnerFinding(
            job: String, body: CI.Workflow.YAML.Mapping, expecting runner: String
        ) -> String? {
            let declared = body["runs-on"].map(\.pythonText) ?? ""
            guard !declared.lowercased().contains(runner) else { return nil }
            return "\(job): runs-on must reference a \(runner) runner per [CI-010]; "
                + "got \(declared.pythonQuoted)"
        }

        static let nightlyMessage = """
            linux-nightly MUST set `continue-on-error: true` per [CI-010] — \
            nightly toolchain failures are tolerated and should not gate CI
            """

        static let windowsMessage = """
            windows-release MUST stay gating per [CI-099] — \
            `continue-on-error: true` is forbidden on this job. Windows is \
            a first-class target platform; advisory-flipping would hide \
            source-level bugs (`#if os(Windows)` divergence, source \
            incompatibilities). The contrast with linux-nightly's posture \
            is intentional: nightly is toolchain-instability noise, Windows \
            release is a target shipped to. If a Windows compiler crash \
            blocks main, file upstream and wait for a compiler fix; do NOT \
            weaken the gate.
            """

        static let missingAppleMessage = """
            required matrix job 'apple-simulator-build' missing from jobs: \
            block per [CI-010] — the Apple-simulator advisory leg \
            (iOS/tvOS/watchOS/visionOS) catches resource-bundle CodeSign \
            failures that swift build/test never surface
            """

        static let appleAdvisoryMessage = """
            apple-simulator-build MUST set `continue-on-error: true` per \
            [CI-021]/[CI-091] during the soak window — the Apple-simulator \
            legs are advisory until green ecosystem-wide
            """

        static func collapsedMatrixMessage(missing: [String]) -> String {
            """
            apple-simulator-build matrix MUST cover all four Apple \
            simulator platforms per [CI-091] uniform-platform-matrix \
            doctrine (never collapsed; M4 REJECT 2026-05-06); missing: \
            \(missing.pythonListLiteral)
            """
        }
    }
}

// MARK: - Message rendering

// `[CI-010]`'s findings quote the offending value back to the reader, and
// the quoting convention is part of the message the control plane has
// aggregated since the rule shipped. It is preserved here rather than
// modernised: a message is a contract with the person reading a check
// annotation, and changing its punctuation during a port would make a
// rewrite look like a behaviour change.

extension CI.Workflow.YAML.Node {
    /// The node rendered the way the retired validator rendered it before
    /// quoting — a scalar as itself, a collection in its literal form.
    fileprivate var pythonText: String {
        switch self {
        case .null: "None"
        case .boolean(let value): value ? "True" : "False"
        case .integer(let value): String(value)
        case .number(let value): String(value)
        case .text(let value): value
        case .sequence(let elements):
            "[" + elements.map(\.pythonRepresentation).joined(separator: ", ") + "]"
        case .mapping(let mapping):
            "{"
                + mapping.entries
                .map { "\($0.key.pythonRepresentation): \($0.value.pythonRepresentation)" }
                .joined(separator: ", ") + "}"
        }
    }

    /// The node as it appears *inside* a rendered collection: text is
    /// quoted, everything else renders as itself.
    fileprivate var pythonRepresentation: String {
        if case .text(let value) = self { return value.pythonQuoted }
        return pythonText
    }
}

extension String {
    /// The string in quotes, single by default and double when the text
    /// contains a single quote but no double quote.
    fileprivate var pythonQuoted: String {
        let quote: Character = contains("'") && !contains("\"") ? "\"" : "'"
        var result = String(quote)
        for character in self {
            switch character {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case quote: result += "\\\(quote)"
            default: result.append(character)
            }
        }
        result.append(quote)
        return result
    }
}

extension [String] {
    fileprivate var pythonListLiteral: String {
        "[" + map(\.pythonQuoted).joined(separator: ", ") + "]"
    }
}
