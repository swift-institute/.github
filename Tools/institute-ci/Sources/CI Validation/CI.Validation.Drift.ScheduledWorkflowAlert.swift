import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation.Drift {
    /// `[SCHEDULED-WORKFLOW-ALERT-DRIFT]` — the alert workflow's watch
    /// list names exactly the workflows that run on a schedule.
    ///
    /// `alert-scheduled-workflow-failure.yml` observes scheduled
    /// control-plane failures through a `workflow_run` trigger, and
    /// Actions requires that trigger to name its subjects literally —
    /// `on.workflow_run.workflows:` takes an exact-name list, not a
    /// wildcard and not a query over `schedule:` triggers. The list is
    /// therefore a second, hand-maintained copy of "which workflows here
    /// run on a schedule", and a scheduled workflow added or renamed
    /// without a matching entry falls silently outside observability —
    /// exactly how `reconcile-project-invariants.yml` went quiet after
    /// `747eeaa5`.
    ///
    /// The scheduled set is discovered from the workflows directory,
    /// never from a roster, and compared with the watch list in **both**
    /// directions:
    ///
    /// - `missing-from-watch-list` — scheduled but unwatched. The silent
    ///   gap.
    /// - `stale-watch-entry` — watched but no longer scheduled. Harmless
    ///   for alerting, and evidence the list stopped tracking reality.
    ///
    /// A workflow's `name:` is the key Actions matches on, so that is the
    /// key compared; a document without one falls back to its filename
    /// stem rather than dropping out of the set.
    public struct ScheduledWorkflowAlert: CI.Validation.Validator {
        public typealias Finding = CI.Validation.Finding

        public let rules: [CI.Validation.Rule] = ["SCHEDULED-WORKFLOW-ALERT-DRIFT"]
        public let retiredScript: String? =
            ".github/scripts/check-scheduled-workflow-alert-parity.py"

        public static let workflowsDirectory = ".github/workflows"
        public static let alertPath = ".github/workflows/alert-scheduled-workflow-failure.yml"

        public init() {}

        public func findings(
            in subject: CI.Validation.Subject
        ) throws(CI.Validation.EnvironmentDefect) -> [Finding] {
            let directory = subject.path(Self.workflowsDirectory)
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { throw .missingSupportFile(path: directory) }
            guard let alertText = try subject.text(at: Self.alertPath) else {
                throw .missingSupportFile(path: subject.path(Self.alertPath))
            }

            let alert = try Self.parse(alertText, at: subject.path(Self.alertPath))
            let watched = try Self.watched(in: alert)

            // `*.yml` only, and the alert workflow excluded — it carries
            // no `schedule:` trigger of its own, so the exclusion is belt
            // and braces rather than load-bearing. Both narrowings are
            // the retired script's; widening either would change which
            // documents the rule reads.
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                throw .unreadableFile(path: directory)
            }
            var scheduled: [String: String] = [:]
            for name in names.sorted()
            where name.hasSuffix(".yml") && name != (Self.alertPath as NSString).lastPathComponent {
                guard let text = try subject.text(at: "\(Self.workflowsDirectory)/\(name)") else {
                    continue
                }
                let document = try Self.parse(text, at: "\(directory)/\(name)")
                guard let mapping = document.mapping else { continue }
                guard Self.triggers(of: mapping)?["schedule"] != nil else { continue }
                let declared = mapping["name"]?.text ?? String(name.dropLast(".yml".count))
                scheduled[declared] = name
            }

            return Self.drift(scheduled: scheduled, watched: watched).map { gap in
                Finding(
                    repository: subject.repository, rule: rules[0],
                    message: "\(gap.surface.rawValue): \(gap.message)")
            }
        }

        /// The two-directional comparison.
        ///
        /// Split out from `findings(in:)` — and taking the two sets
        /// rather than the subject — because the positive controls
        /// perturb one entry of a synthetic pair at a time, and a control
        /// that had to write workflow files to disk would be testing the
        /// filesystem.
        public static func drift(scheduled: [String: String], watched: Set<String>) -> [Gap] {
            var gaps: [Gap] = []
            for name in scheduled.keys.sorted() where !watched.contains(name) {
                gaps.append(
                    Gap(
                        name: name, surface: .missing,
                        message: "'\(scheduled[name] ?? "")' has a schedule: trigger (workflow "
                            + "name '\(name)') but is absent from "
                            + "alert-scheduled-workflow-failure.yml's on.workflow_run.workflows "
                            + "list"))
            }
            for name in watched.sorted() where scheduled[name] == nil {
                gaps.append(
                    Gap(
                        name: name, surface: .stale,
                        message: "'\(name)' is listed in alert-scheduled-workflow-failure.yml's "
                            + "on.workflow_run.workflows list but no workflow in the workflows "
                            + "directory currently has a schedule: trigger with that name"))
            }
            return gaps
        }

        /// The watch list, or a defect when the alert workflow has lost
        /// the shape this rule reads. Not a finding: an unreadable watch
        /// list means the question could not be asked.
        public static func watched(
            in alert: CI.Workflow.YAML.Node
        ) throws(CI.Validation.EnvironmentDefect) -> Set<String> {
            guard let mapping = alert.mapping, let triggers = triggers(of: mapping) else {
                throw .missingSupportFile(
                    path: "alert workflow's on: block has no workflow_run: mapping")
            }
            guard let run = triggers["workflow_run"]?.mapping else {
                throw .missingSupportFile(
                    path: "alert workflow's on: block has no workflow_run: mapping")
            }
            guard let workflows = run["workflows"]?.sequence else {
                throw .missingSupportFile(
                    path: "alert workflow's on.workflow_run has no workflows: list")
            }
            return Set(workflows.compactMap(\.text))
        }

        /// A workflow's `on:` mapping.
        ///
        /// The bare key `on` resolves to the **boolean** `true` under
        /// YAML 1.1, so the lookup is two steps in a fixed order — the
        /// string key first, the boolean key second — matching
        /// `validate_lib.parse_on_block`. A reader that skipped the
        /// second step would see no triggers on any workflow and report
        /// perfect health.
        static func triggers(of mapping: CI.Workflow.YAML.Mapping) -> CI.Workflow.YAML.Mapping? {
            (mapping["on"] ?? mapping[node: .boolean(true)])?.mapping
        }

        /// A parse failure here is a defect, not a finding: the retired
        /// script exited 2 on any unreadable document in the directory,
        /// because a checker that skipped what it could not read would
        /// under-report the scheduled set and call the watch list clean.
        static func parse(
            _ text: String, at path: String
        ) throws(CI.Validation.EnvironmentDefect) -> CI.Workflow.YAML.Node {
            do throws(CI.Workflow.YAML.Error) {
                return try CI.Workflow.YAML.Parser.parse(text)
            } catch {
                throw .missingSupportFile(path: "\(path) (YAML parse failed: \(error.message))")
            }
        }
    }
}

extension CI.Validation.Drift.ScheduledWorkflowAlert {
    /// Which direction of the comparison a gap came from.
    public enum Surface: String, Sendable, CaseIterable {
        case missing = "missing-from-watch-list"
        case stale = "stale-watch-entry"
    }

    /// One workflow out of correspondence with the watch list.
    public struct Gap: Sendable, Equatable {
        public let name: String
        public let surface: Surface
        public let message: String

        public init(name: String, surface: Surface, message: String) {
            self.name = name
            self.surface = surface
            self.message = message
        }
    }
}
