import CI_Contract
import CI_Workflow

extension CI.Inventory {
    /// One job of the universal workflow, as the verdict sees it.
    public struct Job: Sendable, Equatable {
        /// The job id — the key under `jobs:`, and the identifier every
        /// `needs:` list, the plan's leg vocabulary, and
        /// `CI.Contract.Leg` all use.
        public let id: String

        /// The job's `name:`, unexpanded.
        ///
        /// Retained because it is the only bridge between this inventory
        /// and a real run: the Actions API reports jobs by rendered
        /// display name, never by id, so verifying an inventory against
        /// a hosted run means matching these — with `${{ }}` expansions
        /// substituted — against `ci / matrix / <name>`.
        public let displayName: String?

        /// `runs-on` when the job runs steps, `uses` when it delegates.
        ///
        /// Unresolved, because `runs-on` is legally a scalar, a label
        /// list, or a runner-group mapping, and the pool a job lands on
        /// is exactly the kind of fact an inventory must not narrow.
        public let runner: CI.Workflow.YAML.Node?

        /// The jobs this one waits for, normalised to a list. Actions
        /// allows a bare scalar; the DAG does not care which spelling
        /// was used.
        public let needs: [String]

        /// The job's `if:`, verbatim. Not evaluated — an unexpanded
        /// expression is the honest content of this field, and any
        /// attempt to resolve it here would be resolving it against a
        /// context that does not exist outside a run.
        public let condition: String?

        public let continueOnError: Bool

        /// True when the job's `if:` mentions
        /// `github.event.repository.private`.
        ///
        /// The private-visibility guard is a coverage fact, not a
        /// styling one: a guarded job reports **no signal at all** on a
        /// private repository, so a gating job that carries the guard is
        /// a gating job that is silently absent there.
        public let privateGuarded: Bool

        /// The job's `strategy.matrix`, unresolved.
        ///
        /// Kept as a node rather than modelled. A matrix axis holds
        /// literal lists, `include`/`exclude` blocks, and `${{ }}`
        /// expressions; a typed model here would have to either reject
        /// legal shapes or grow into a second matrix evaluator. The
        /// inventory's job is to record what is shipped.
        public let matrixAxes: CI.Workflow.YAML.Node?

        /// The job's `permissions:` block, unresolved, for the same
        /// reason: `permissions: read-all` is a scalar, `permissions:`
        /// is an explicit empty, and an absent key inherits — three
        /// distinct token boundaries that a `[String: String]` would
        /// flatten into one.
        public let permissions: CI.Workflow.YAML.Node?

        /// True when some step body mentions `Tests/Package.swift` —
        /// the nested test package execution site.
        public let nestedTestExecution: Bool

        /// Every step's `name:`, in order, with `nil` for an unnamed
        /// step. Positional, not a name list: dropping the unnamed steps
        /// would renumber every step after them, and a step's index is
        /// how a run's logs are read back.
        public let stepNames: [String?]

        public let posture: Posture

        /// The job's DAG wave: 0 with no `needs`, else one more than the
        /// deepest job it needs.
        ///
        /// This is what makes an aggregate an aggregate. `ci-ok` needs
        /// every gating leg, so it necessarily sits at a strictly higher
        /// wave than all of them and cannot acquire a runner until they
        /// have finished.
        public let wave: Int

        public var hasMatrix: Bool { matrixAxes != nil }

        /// The canonical-JSON node for this job.
        public var node: CI.Workflow.YAML.Node {
            .mapping(
                .init([
                    (.text("name"), displayName.map(CI.Workflow.YAML.Node.text) ?? .null),
                    (.text("runner"), runner ?? .null),
                    (.text("needs"), .sequence(needs.map(CI.Workflow.YAML.Node.text))),
                    (.text("if"), condition.map(CI.Workflow.YAML.Node.text) ?? .null),
                    (.text("continue_on_error"), .boolean(continueOnError)),
                    (.text("private_guarded"), .boolean(privateGuarded)),
                    (.text("has_matrix"), .boolean(hasMatrix)),
                    (.text("matrix_axes"), matrixAxes ?? .null),
                    (.text("permissions"), permissions ?? .null),
                    (.text("nested_test_execution"), .boolean(nestedTestExecution)),
                    (
                        .text("step_names"),
                        .sequence(stepNames.map { $0.map(CI.Workflow.YAML.Node.text) ?? .null })
                    ),
                    (.text("posture"), .text(posture.rawValue)),
                    (.text("wave"), .integer(wave)),
                ]))
        }
    }
}
