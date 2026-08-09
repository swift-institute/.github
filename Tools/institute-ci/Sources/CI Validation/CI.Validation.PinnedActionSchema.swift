import CI_Contract
import CI_Workflow
import Foundation

extension CI.Validation {
    /// `[CI-118]` -- a caller of a same-repo pinned composite action must
    /// pass only inputs the pinned revision declares, and must gate only
    /// on outputs the pinned revision -- of the SPECIFIC step being
    /// referenced -- actually sets.
    ///
    /// Origin: PR #500's original head (`d1d67da`) pinned
    /// `install-swift-sdk@d1af72d0` and passed `skip-on-missing-release`,
    /// an input that pinned revision did not declare, then gated a build
    /// step on `steps.install.outputs.installed`, an output that
    /// revision did not set either. GitHub only *warns* on an undeclared
    /// `with:` key and silently resolves a missing output reference to
    /// an empty string, so `if: steps.install.outputs.installed ==
    /// 'true'` would have evaluated false forever -- three SDK legs
    /// permanently green without ever compiling, and all twelve hosted
    /// gates green because nothing modeled caller/action schema
    /// correspondence across the self-referential pin. Found only by
    /// human review (`swift-institute/.github#501`); this rule is the
    /// gap that closes.
    ///
    /// Resolution is delegated to `PinnedContent`, which reads the
    /// pinned revision's `action.yml` via git object access rather than
    /// the working tree -- a call site pinned to an older or newer
    /// commit than what happens to be checked out is still checked
    /// against the revision it actually names. An unreachable pinned
    /// object is itself a finding (`PinnedContent` fails closed); this
    /// rule never treats "could not resolve" as "assume it is fine".
    ///
    /// `[CI-117]` (`CompositeActionPins`) verifies only that the
    /// self-referential `uses:` ref is a full 40-hex identity pin -- a
    /// FORMAT check, unrelated to and untouched by this rule. It is a
    /// candidate future consumer of `PinnedContent` to resolve the
    /// pinned blob it currently only regex-matches the ref text of, but
    /// that rewiring is out of scope here.
    public struct PinnedActionSchema: Validator {
        public static let rule: Rule = "CI-118"
        public let rules: [Rule] = [Self.rule]
        public let retiredScript: String? = nil

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let (documents, refusals) = try subject.workflows(citing: Self.rule)
            var findings = refusals
            for document in documents {
                findings += Self.findings(in: document, subject: subject)
            }
            return findings
        }

        /// The `uses:` path prefix this rule's coordinates are scoped
        /// to. Shared with `[CI-117]` so the two rules agree on which
        /// `uses:` lines are "this repository's own composite actions"
        /// without either one re-deriving the other's constant.
        static var referencePrefix: String { CompositeActionPins.referencePrefix }

        static func findings(in document: CI.Workflow.Document, subject: Subject) -> [Finding] {
            var findings: [Finding] = []

            // The declared schema of every step THIS rule could resolve,
            // keyed by step id -- never by action name. Two steps in the
            // same job can pin the same action under different ids, and
            // an outputs reference is scoped to one step's id, not to
            // "an action that happens to declare this output somewhere
            // in the file". A step with no `id:` cannot be referenced by
            // `steps.<id>.outputs...` at all, so it contributes nothing
            // here regardless of whether it resolved.
            var schemaByStepID: [String: PinnedContent.Schema] = [:]

            for job in document.jobs {
                for step in job.steps {
                    guard
                        let uses = step["uses"]?.text,
                        let coordinate = PinnedContent.coordinate(
                            uses: uses, referencePrefix: Self.referencePrefix)
                    else { continue }

                    switch PinnedContent.resolve(coordinate, gitRoot: subject.root) {
                    case .unreachable(let reason):
                        findings.append(
                            Self.unreachableFinding(
                                document: document, job: job, uses: uses,
                                reason: reason, repository: subject.repository))

                    case .resolved(let schema):
                        if let stepID = step["id"]?.text {
                            schemaByStepID[stepID] = schema
                        }
                        findings += Self.undeclaredInputFindings(
                            document: document, job: job, uses: uses,
                            with: step["with"]?.mapping, schema: schema,
                            repository: subject.repository)
                    }
                }
            }

            findings += Self.absentOutputFindings(
                document: document, schemaByStepID: schemaByStepID,
                repository: subject.repository)
            return findings
        }

        // MARK: - `with:` keys ⊆ declared inputs

        static func undeclaredInputFindings(
            document: CI.Workflow.Document, job: CI.Workflow.Job, uses: String,
            with: CI.Workflow.YAML.Mapping?, schema: PinnedContent.Schema,
            repository: String
        ) -> [Finding] {
            // Only the KEYS are compared. A `with:` value is legitimately
            // a `${{ ... }}` expression resolved at runtime -- the shape
            // of the value is never this rule's business, only whether
            // the key itself is a declared input.
            let passed = Set(with?.textKeys ?? [])
            let undeclared = passed.subtracting(schema.inputs)
            guard !undeclared.isEmpty else { return [] }
            return undeclared.sorted().map { key in
                Finding(
                    repository: repository, rule: Self.rule,
                    message: "\(document.name): job `\(job.name)` step `\(uses)` passes "
                        + "`with: \(key)`, which the pinned revision does not declare as "
                        + "an input -- GitHub only warns on this, it never fails the run.")
            }
        }

        // MARK: - `steps.<id>.outputs.<name>` ∈ declared outputs of THAT step's action

        static func absentOutputFindings(
            document: CI.Workflow.Document, schemaByStepID: [String: PinnedContent.Schema],
            repository: String
        ) -> [Finding] {
            var texts: [String] = []
            Self.collectScalarText(document.root, into: &texts)
            var findings: [Finding] = []
            for text in texts {
                for reference in Self.outputReferences(in: text) {
                    // Scoped strictly to this document's own resolved
                    // pinned-composite steps: a reference naming a step
                    // id this rule never resolved (a different action
                    // family, a reusable job, an unpinned/unresolvable
                    // step) is out of scope -- reporting there would be
                    // a guess, not a finding.
                    guard let schema = schemaByStepID[reference.stepID] else { continue }
                    guard !schema.outputs.contains(reference.output) else { continue }
                    findings.append(
                        Finding(
                            repository: repository, rule: Self.rule,
                            message: "\(document.name): `steps.\(reference.stepID).outputs."
                                + "\(reference.output)` -- step `\(reference.stepID)`'s "
                                + "pinned action does not declare that output; it silently "
                                + "resolves to an empty string, never a run failure."))
                }
            }
            return findings
        }

        /// One `steps.<id>.outputs.<name>` reference found in a scalar.
        struct OutputReference: Equatable {
            let stepID: String
            let output: String
        }

        /// Every `steps.<id>.outputs.<name>` occurrence in `text`, found
        /// by a bounded manual scan rather than a regex library, in the
        /// style `CI.Validation.SchemaCorrespondence` already uses for
        /// `.settings.<key>`.
        static func outputReferences(in text: String) -> [OutputReference] {
            let marker = "steps."
            var references: [OutputReference] = []
            var remainder = text[...]
            while let range = remainder.range(of: marker) {
                remainder = remainder[range.upperBound...]
                guard let stepID = Self.identifier(consuming: &remainder) else { continue }
                guard remainder.hasPrefix(".outputs.") else { continue }
                remainder = remainder.dropFirst(".outputs.".count)
                guard let output = Self.identifier(consuming: &remainder) else { continue }
                references.append(OutputReference(stepID: String(stepID), output: String(output)))
            }
            return references
        }

        /// Consumes a leading `[A-Za-z0-9_-]+` identifier from
        /// `remainder`, returning `nil` (and consuming nothing) when the
        /// next character does not start one.
        static func identifier(consuming remainder: inout Substring) -> Substring? {
            let identifier = remainder.prefix {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
            }
            guard !identifier.isEmpty else { return nil }
            remainder = remainder.dropFirst(identifier.count)
            return identifier
        }

        /// Every string-scalar value reachable from `node`, gathered
        /// recursively -- mapping values and sequence elements, so an
        /// `outputs.<name>` reference inside a multi-line `run:` block,
        /// an `if:`, or an `env:` value is all found the same way,
        /// regardless of which key holds it.
        static func collectScalarText(_ node: CI.Workflow.YAML.Node, into texts: inout [String]) {
            switch node {
            case .text(let value):
                texts.append(value)
            case .sequence(let elements):
                for element in elements { Self.collectScalarText(element, into: &texts) }
            case .mapping(let mapping):
                for entry in mapping.entries { Self.collectScalarText(entry.value, into: &texts) }
            case .null, .boolean, .integer, .number:
                break
            }
        }

        // MARK: - Fail-closed: an unreachable pinned object

        static func unreachableFinding(
            document: CI.Workflow.Document, job: CI.Workflow.Job, uses: String,
            reason: String, repository: String
        ) -> Finding {
            Finding(
                repository: repository, rule: Self.rule,
                message: "\(document.name): job `\(job.name)` step `\(uses)` -- pinned "
                    + "object unreachable, cannot verify the caller against its declared "
                    + "schema (failing closed rather than skipping): \(reason)")
        }
    }
}
