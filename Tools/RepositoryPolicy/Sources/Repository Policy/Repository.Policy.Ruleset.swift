import Foundation

extension RepositoryPolicy {
    /// The Institute protected-main branch ruleset contracts, converged by
    /// `sync-metadata`'s `rulesets` job and read back for drift detection.
    ///
    /// Two classes exist. `protectedMainPayload` is the package contract:
    /// package repositories emit the `ci / ci-ok` status check, so it carries
    /// a `required_status_checks` rule requiring that context. Control-plane
    /// repositories (`.github` repos, Workspace, Research, Issues) never
    /// produce that check, so `protectedMainControlPayload` is the same
    /// contract minus the `required_status_checks` rule entirely — its
    /// absence is fail-closed enforced by the validator, not merely
    /// unchecked. The `rulesets` job classifies each target repository
    /// mechanically (root `Package.swift` present ⇒ package; absent ⇒
    /// control) and applies the class-correct contract
    /// (swift-institute/.github#200).
    ///
    /// Break-glass: in a genuine emergency, an organization admin may delete
    /// the "Institute protected main" (or "Institute protected main
    /// (control)") ruleset directly on the affected repository to bypass
    /// enforcement. This bypass requires a durable receipt comment on the
    /// owning issue naming who performed it, why, and when. Once the
    /// emergency is over, the ruleset must be re-applied by dispatching
    /// `sync-metadata` with `apply-rulesets: true` against that repository —
    /// never left deleted or hand-recreated.
    ///
    /// A deleted ruleset is re-applied by the next nightly unless the
    /// owning-issue receipt says otherwise (swift-institute/.github#204).
    /// Mechanically, a break-glass-deleted ruleset and a repository that has
    /// never been enrolled look identical from current GitHub state alone,
    /// so the scheduled/nightly sweep's `SweepMode.scheduledHeal` posture
    /// (below) leaves an absent ruleset reported, not recreated — the
    /// scheduled path by itself does not restore it. The expected default is
    /// prompt restoration: an explicit `apply-rulesets: true` dispatch is the
    /// one path that recreates it. A repository deliberately left without
    /// enforcement past the emergency window needs that decision recorded on
    /// the owning issue's receipt; absent that receipt, restore promptly
    /// rather than let the bypass linger.
    public enum Ruleset {
        public static func protectedMainPayload(from url: URL) throws -> Data {
            let (object, rules) = try identity(
                from: url,
                expectedName: "Institute protected main"
            )
            guard
                Set(rules.compactMap { $0["type"] as? String }) == [
                    "deletion", "non_fast_forward", "pull_request", "required_status_checks",
                ]
            else {
                throw ConfigurationError(
                    "protected-main ruleset rules differ from the Institute contract"
                )
            }
            try validatePullRequestRule(rules)
            guard
                let checks = rules.first(where: {
                    $0["type"] as? String == "required_status_checks"
                })?["parameters"] as? [String: Any],
                checks["strict_required_status_checks_policy"] as? Bool == true,
                checks["do_not_enforce_on_create"] as? Bool == false,
                let required = checks["required_status_checks"] as? [[String: Any]],
                required.count == 1, required.first?["context"] as? String == "ci / ci-ok"
            else {
                throw ConfigurationError(
                    "protected-main status-check transaction differs from the Institute contract"
                )
            }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }

        /// The control-plane variant: identical protections minus the
        /// required-status-check rule, since control-plane repositories emit
        /// no `ci / ci-ok`. Its rule-type set is exactly `deletion`,
        /// `non_fast_forward`, `pull_request` — a payload carrying a fourth
        /// rule of any type (including a smuggled `required_status_checks`)
        /// fails closed, as does a package-shaped payload (wrong name, and a
        /// `required_status_checks` rule the control set does not admit).
        public static func protectedMainControlPayload(from url: URL) throws -> Data {
            let (object, rules) = try identity(
                from: url,
                expectedName: "Institute protected main (control)"
            )
            guard
                Set(rules.compactMap { $0["type"] as? String }) == [
                    "deletion", "non_fast_forward", "pull_request",
                ]
            else {
                throw ConfigurationError(
                    "protected-main control ruleset rules differ from the Institute contract"
                )
            }
            try validatePullRequestRule(rules)
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }

        /// Shared identity checks both contract classes require: schema
        /// version, name/target/enforcement, no bypass actors, and the
        /// main-only ref-name condition. Returns the schema-stripped object
        /// together with its raw `rules` array for the caller's
        /// class-specific rule validation.
        private static func identity(
            from url: URL,
            expectedName: String
        ) throws -> (object: [String: Any], rules: [[String: Any]]) {
            let source = try Data(contentsOf: url)
            guard var object = try JSONSerialization.jsonObject(with: source) as? [String: Any]
            else {
                throw ConfigurationError("protected-main ruleset must be a JSON object")
            }
            guard (object.removeValue(forKey: "schemaVersion") as? Int) == 1 else {
                throw ConfigurationError("unsupported protected-main ruleset schema")
            }
            guard object["name"] as? String == expectedName,
                object["target"] as? String == "branch",
                object["enforcement"] as? String == "active"
            else {
                throw ConfigurationError("protected-main ruleset identity is invalid")
            }
            guard let bypass = object["bypass_actors"] as? [Any], bypass.isEmpty else {
                throw ConfigurationError("protected-main ruleset permits a bypass actor")
            }
            guard let conditions = object["conditions"] as? [String: Any],
                let reference = conditions["ref_name"] as? [String: Any],
                (reference["include"] as? [String]) == ["refs/heads/main"],
                (reference["exclude"] as? [String]) == []
            else {
                throw ConfigurationError("protected-main ruleset must select only main")
            }
            guard let rules = object["rules"] as? [[String: Any]] else {
                throw ConfigurationError(
                    "protected-main ruleset rules differ from the Institute contract"
                )
            }
            return (object, rules)
        }

        /// The pull-request transaction both contract classes pin identically.
        private static func validatePullRequestRule(_ rules: [[String: Any]]) throws {
            guard
                let review = rules.first(where: { $0["type"] as? String == "pull_request" })?[
                    "parameters"
                ] as? [String: Any], review["required_approving_review_count"] as? Int == 1,
                review["dismiss_stale_reviews_on_push"] as? Bool == true,
                review["require_last_push_approval"] as? Bool == true,
                review["required_review_thread_resolution"] as? Bool == true,
                review["require_code_owner_review"] as? Bool == false,
                // GitHub server-canonicalizes these three fields onto every
                // pull_request rule even when the contract omits them, which
                // fails the fail-closed read-back comparison in
                // sync-metadata.yml's `rulesets` job. Pinning them here keeps
                // the contract, the applied ruleset, and its read-back in
                // exact correspondence, and keeps merge-method policy
                // (squash-only) an explicit, enforced fact rather than an
                // unpinned server default.
                review["allowed_merge_methods"] as? [String] == ["squash"],
                let requiredReviewers = review["required_reviewers"] as? [Any],
                requiredReviewers.isEmpty,
                let dismissalRestriction = review["dismissal_restriction"] as? [String: Any],
                dismissalRestriction["enabled"] as? Bool == false,
                let allowedActors = dismissalRestriction["allowed_actors"] as? [Any],
                allowedActors.isEmpty
            else {
                throw ConfigurationError(
                    "protected-main pull-request transaction differs from the Institute contract"
                )
            }
        }
    }
}
