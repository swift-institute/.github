import CI_Contract
import CI_Workflow

extension CI.Inventory {
    /// The `plan` job, inventoried: where the subject is resolved, where
    /// the tier is classified, and who owns the leg vocabulary.
    ///
    /// The last field is the one that changed. The retired inventory
    /// re-extracted the full-tier leg list from a `LEGS="…"` shell
    /// literal in the "Classify tier" step body with a regular
    /// expression. That literal is gone: the step now shells out to
    /// `institute-ci plan` and reads the answer back with `jq`, so the
    /// regular expression has been matching nothing and the committed
    /// corpus has been recording `"full_tier_legs": []` — an empty
    /// vocabulary — as the shipped truth.
    ///
    /// The vocabulary is therefore taken from its actual owner,
    /// `CI.Contract.Plan`, and the workflow is inventoried for the fact
    /// that it delegates to that owner rather than re-deriving it. A
    /// workflow that stopped delegating would flip
    /// `delegatesToInstituteCI` and fail the drift test, which is the
    /// signal the regular expression was supposed to give and no longer
    /// could.
    public struct Plan: Sendable, Equatable {
        public static let resolveSubjectStep = "Resolve CI subject"
        public static let classifyStep = "Classify tier"

        /// The type that owns the leg vocabulary this workflow plans by.
        public static let legVocabularyOwner = "CI.Contract.Plan"

        /// True when the "Classify tier" step invokes `institute-ci plan`.
        public let delegatesToInstituteCI: Bool

        /// The full tier's leg ids, from `CI.Contract.Plan` — the owner,
        /// asked with no forced platform support and the institute lint
        /// bundle.
        public static var fullTierLegs: [String] {
            do throws(CI.Contract.Plan.Error) {
                return try CI.Contract.Plan(
                    forcedTier: "full", ref: "", event: "", lintBundle: "institute")
                    .legs.map(\.id)
            } catch {
                // The owner refusing its own full tier under no platform
                // filter would mean the vocabulary has no members, which
                // the drift test reports rather than this accessor.
                return []
            }
        }

        public init(delegatesToInstituteCI: Bool) {
            self.delegatesToInstituteCI = delegatesToInstituteCI
        }

        public var node: CI.Workflow.YAML.Node {
            .mapping(
                .init([
                    (.text("resolve_subject_step"), .text(Self.resolveSubjectStep)),
                    (.text("classify_step"), .text(Self.classifyStep)),
                    (.text("delegates_to_institute_ci"), .boolean(delegatesToInstituteCI)),
                    (.text("leg_vocabulary_owner"), .text(Self.legVocabularyOwner)),
                    (
                        .text("full_tier_legs"),
                        .sequence(Self.fullTierLegs.map(CI.Workflow.YAML.Node.text))
                    ),
                ]))
        }
    }
}
