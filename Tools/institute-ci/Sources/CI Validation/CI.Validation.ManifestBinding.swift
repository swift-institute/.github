import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// `[CI-MANIFEST-BINDING]` — `validators-manifest.yaml` is internally
    /// consistent.
    ///
    /// The manifest is the single source of truth binding rule id ↔
    /// validator script ↔ workflow file, so it is the one document whose
    /// drift makes every other gate unreliable. Three checks, numbered as
    /// the retired script numbered them (checks 1 and 3 — the Skills
    /// bracket-citation cross-references — were retired by principal
    /// ruling on `swift-institute/.github#229`):
    ///
    /// - **check 2** — every `validate-*.py` on disk is referenced by at
    ///   least one entry. Catches a validator added without a manifest
    ///   entry.
    /// - **check 4** — a `deprecated` entry clears both
    ///   `validator-script` and `workflow-file`. Catches ghost lint: an
    ///   entry left pointing at a retired script.
    /// - **check 5** — an `active` + `self-firing: active` entry with a
    ///   `workflow-file` resolves to a workflow on disk carrying **both**
    ///   `push:` and `pull_request:` at the top level of `on:`. Catches
    ///   the manifest-says-active-but-the-workflow-is-`workflow_call`-only
    ///   shape that hid `CI-090`/`CI-097` for nine days.
    ///
    /// Plus schema sanity: every entry is a mapping carrying the full key
    /// set, with a status in the enum.
    ///
    /// ## The fixture stubs are permanent
    ///
    /// Check 2 scans for `validate-*.py` **files**, and the fixture
    /// corpus under `.github/scripts/tests/fixtures/ci-manifest-binding/`
    /// carries two-line Python stubs (`validate-foo.py`,
    /// `validate-stub.py`, …) that exist purely to be found by that scan.
    /// They are **data, not code**, and they are a permanent principled
    /// exception to the Swift-purity end state (adjudication on
    /// `swift-institute/.github#404`, comment 5213427716 §2): porting or
    /// deleting them does not finish the purity job, it voids this rule's
    /// corpus. This validator is the surface that owns them, so the
    /// exception is written down here rather than in a document a later
    /// sweep will not read.
    ///
    /// For the same reason check 2 keeps scanning for `.py` and not for
    /// Swift files. The predicate is "the manifest knows about every
    /// validator artefact in the subject repository", and in a *subject*
    /// repository — including all seven fixture repositories — that
    /// artefact is still spelled `validate-*.py`.
    public struct ManifestBinding: Validator {
        public let rules: [Rule] = ["CI-MANIFEST-BINDING"]
        public let retiredScript: String? = ".github/scripts/validate-manifest-binding.py"

        /// Every key a manifest entry must carry, per
        /// `CI-REVIEW-PHASE-B-DESIGN §3`.
        static let requiredKeys: Set<String> = [
            "rule-id", "validator-script", "workflow-file", "status", "self-firing",
            "discovery-mode", "rule-id-regex",
        ]

        static let validStatuses: Set<String> = ["active", "deferred", "deprecated"]

        static let manifestPath = ".github/scripts/validators-manifest.yaml"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            func finding(_ message: String) -> Finding {
                Finding(repository: subject.repository, rule: rule, message: message)
            }

            guard let text = try subject.text(at: Self.manifestPath) else {
                return [
                    finding(
                        "manifest missing: \(Self.manifestPath) MUST exist per "
                            + "[CI-MANIFEST-BINDING] (single source-of-truth for rule-ID ↔ "
                            + "validator-script binding).")
                ]
            }

            let document: CI.Workflow.YAML.Node
            do throws(CI.Workflow.YAML.Error) {
                document = try CI.Workflow.YAML.Parser.parse(text)
            } catch {
                return [finding("manifest YAML parse failed: \(error.message)")]
            }

            guard let top = document.mapping else {
                return [finding("manifest top-level MUST be a mapping with a 'validators:' key.")]
            }
            guard let entries = top["validators"]?.sequence else {
                return [finding("manifest MUST contain a 'validators:' list at top level.")]
            }

            var findings: [Finding] = []
            var referencedScripts: Set<String> = []

            for (index, entry) in entries.enumerated() {
                guard let entry = entry.mapping else {
                    findings.append(
                        finding("entry #\(index): not a mapping (got \(Retired.typeName(entry)))."))
                    continue
                }

                let keys = Set(entry.textKeys)
                let missing = Self.requiredKeys.subtracting(keys)
                if !missing.isEmpty {
                    let identifier = entry["rule-id"].map(Retired.value) ?? Retired.quoted("#\(index)")
                    findings.append(
                        finding(
                            "entry \(identifier): missing required keys "
                                + "\(Retired.list(missing.sorted())) — every manifest entry "
                                + "MUST carry the full schema per CI-REVIEW-PHASE-B-DESIGN §3."))
                    continue
                }

                let identifier = entry["rule-id"].map(Retired.value) ?? "None"
                let status = entry["status"] ?? .null

                guard let statusText = status.text, Self.validStatuses.contains(statusText) else {
                    findings.append(
                        finding(
                            "entry \(identifier): invalid status \(Retired.value(status)) — "
                                + "must be one of \(Retired.list(Self.validStatuses.sorted())) "
                                + "per [CI-MANIFEST-BINDING]."))
                    continue
                }

                if statusText == "deprecated" {
                    if let script = entry["validator-script"], Retired.isTruthy(script) {
                        findings.append(
                            finding(
                                "entry \(identifier): status=deprecated but validator-script is "
                                    + "non-empty (\(Retired.value(script))) — deprecated "
                                    + "entries MUST clear validator-script per "
                                    + "[CI-MANIFEST-BINDING] check 4 (prevents ghost lint via "
                                    + "stale script reference)."))
                    }
                    if let workflow = entry["workflow-file"], Retired.isTruthy(workflow) {
                        findings.append(
                            finding(
                                "entry \(identifier): status=deprecated but workflow-file is "
                                    + "non-empty (\(Retired.value(workflow))) — deprecated "
                                    + "entries MUST clear workflow-file per [CI-MANIFEST-BINDING] "
                                    + "check 4."))
                    }
                }

                if statusText == "active", entry["self-firing"]?.text == "active",
                    let workflowFile = entry["workflow-file"]?.text, !workflowFile.isEmpty
                {
                    findings.append(
                        contentsOf: try Self.selfFiring(
                            entry: identifier, workflowFile: workflowFile, subject: subject,
                            finding: finding))
                }

                // Collected for check 2 at any status. A non-empty
                // deprecated path is already flagged by check 4, and
                // counting it here is what stops check 2 double-firing on
                // the same defect.
                if let script = entry["validator-script"]?.text, !script.isEmpty {
                    referencedScripts.insert(script)
                }
            }

            findings.append(
                contentsOf: try Self.orphans(
                    referenced: referencedScripts, subject: subject, finding: finding))
            return findings
        }

        /// Check 5 for one entry.
        ///
        /// An entry with an empty `workflow-file` is orchestrator-embedded
        /// — fired from a cron sweeper rather than by its own workflow —
        /// and is exempt; the caller filters those before reaching here.
        static func selfFiring(
            entry identifier: String,
            workflowFile: String,
            subject: Subject,
            finding: (String) -> Finding
        ) throws(EnvironmentDefect) -> [Finding] {
            guard let text = try subject.text(at: workflowFile) else {
                return [
                    finding(
                        "entry \(identifier): declared self-firing: active but workflow-file "
                            + "\(Retired.quoted(workflowFile)) does not exist on disk — per "
                            + "[CI-MANIFEST-BINDING] check 5, every active self-firing entry MUST "
                            + "resolve to an on-disk workflow.")
                ]
            }
            let document: CI.Workflow.YAML.Node
            do throws(CI.Workflow.YAML.Error) {
                document = try CI.Workflow.YAML.Parser.parse(text)
            } catch {
                return [
                    finding(
                        "entry \(identifier): workflow-file "
                            + "\(Retired.quoted(workflowFile)) YAML parse failed: "
                            + "\(error.message)")
                ]
            }
            guard let mapping = document.mapping else { return [] }
            let triggers = Self.triggerKeys(of: mapping)
            let missing = ["pull_request", "push"].filter { !triggers.contains($0) }
            guard !missing.isEmpty else { return [] }
            return [
                finding(
                    "entry \(identifier): declared self-firing: active in manifest but "
                        + "workflow-file \(Retired.quoted(workflowFile)) missing trigger(s) "
                        + "\(Retired.list(missing.sorted())) at top level of `on:` (has: "
                        + "\(Retired.list(triggers.sorted()))) — per [CI-MANIFEST-BINDING] "
                        + "check 5 (catches the manifest-says-active-but-workflow-is-"
                        + "workflow_call-only failure mode).")
            ]
        }

        /// The top-level trigger names of a workflow's `on:` block.
        ///
        /// The `on:` key resolves to the **boolean** `true` under YAML
        /// 1.1, which is why a quoted `"on"` and a bare `on` are two
        /// different lookups. The retired script recovered this with
        /// `data.get(True)` after `data.get("on")` missed; the same two
        /// steps in the same order are what makes this reader agree with
        /// it. Omitting the second step false-positives check 5 on every
        /// workflow in the repository.
        ///
        /// Three `on:` shapes are read, matching the retired script:
        /// mapping (its keys), sequence (its items), and a bare scalar
        /// (itself). Anything else is no triggers at all.
        static func triggerKeys(of mapping: CI.Workflow.YAML.Mapping) -> Set<String> {
            let block = mapping["on"] ?? mapping[node: .boolean(true)]
            switch block {
            case .mapping(let value): return Set(value.textKeys)
            case .sequence(let value): return Set(value.compactMap(\.text))
            case .text(let value): return [value]
            default: return []
            }
        }

        /// Check 2 — every `validate-*.py` on disk carries a manifest
        /// entry.
        static func orphans(
            referenced: Set<String>,
            subject: Subject,
            finding: (String) -> Finding
        ) throws(EnvironmentDefect) -> [Finding] {
            let directory = subject.path(".github/scripts")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return [] }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                throw EnvironmentDefect.unreadableFile(path: directory)
            }
            return names
                .filter { $0.hasPrefix("validate-") && $0.hasSuffix(".py") }
                .sorted()
                .map { ".github/scripts/\($0)" }
                .filter { !referenced.contains($0) }
                .map { relative in
                    finding(
                        "validator \(Retired.quoted(relative)) exists on disk but has no "
                            + "manifest entry — every active .github/scripts/validate-*.py MUST be "
                            + "referenced by ≥1 manifest entry per [CI-MANIFEST-BINDING] check 2 "
                            + "(prevents orphan validator drift).")
                }
        }
    }
}
