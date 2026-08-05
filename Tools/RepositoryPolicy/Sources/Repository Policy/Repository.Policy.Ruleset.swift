import Foundation

extension RepositoryPolicy {
    /// The Institute protected-main branch ruleset contracts, converged by
    /// `sync-metadata`'s `rulesets` job and read back for drift detection.
    ///
    /// Two independent dimensions select the applicable payload
    /// (swift-institute/.github#276 Task 3-01):
    ///
    /// - **Class** (already realized by `#200`/`#266`): `package` vs
    ///   `control-plane` vs a declared override. `protectedMainPayload`
    ///   family covers `package`; `protectedMainControlPayload` covers
    ///   `control-plane` and never carries a `required_status_checks` rule
    ///   at all — its absence is fail-closed enforced by the validator, not
    ///   merely unchecked.
    /// - **Visibility** (Task 3-01, new): a `package`-class repository's
    ///   required-check *context* depends on whether it is public or
    ///   private. This is NOT a third top-level `RepositoryClass` case —
    ///   visibility is an observable runtime property read live from GitHub
    ///   (`GET /repos/{full_name}` → `.visibility`), never a declared
    ///   policy file, and never defaulted when unreadable (fail-closed
    ///   `UNMEASURED` at the caller). A public package emits
    ///   `ci / matrix / ci-ok` (the universal chain's own aggregate,
    ///   rendered through a layer wrapper's `matrix` job — the caller-path
    ///   prefix the wrapper's now-temporary `ci-ok` compatibility job used
    ///   to shadow at `ci / ci-ok`, swift-institute/.github#276 Task 1-04).
    ///   A private package emits `verification / workspace` (the trusted
    ///   control-plane receipt, Task 2-01/2-02, swift-institute/.github#253)
    ///   instead — it never runs the public universal chain at all
    ///   ([known-broken-instrument #10]: a private repository's universal CI
    ///   run is zero signal, every job there is visibility-guarded).
    ///
    /// Three package-class payloads exist for the migration window:
    ///
    /// - `protectedMainPayload` — the **target** public contract: requires
    ///   exactly `ci / matrix / ci-ok`. Fleet-final state once every
    ///   layer wrapper's temporary `ci-ok` compatibility aggregate is
    ///   deleted (Task 3-02 step 7).
    /// - `protectedMainPublicCompatibilityPayload` — the **migration**
    ///   public contract: requires BOTH `ci / ci-ok` (the layer wrapper's
    ///   still-live temporary aggregate) AND `ci / matrix / ci-ok` (the
    ///   universal chain's own aggregate, already live underneath it).
    ///   Both producers run unconditionally on every push during the
    ///   overlap window, so both contexts always report; retaining the old
    ///   producer as a second required context (not an either/or) is what
    ///   keeps a wave reversible without ever leaving a repository unable
    ///   to satisfy its required checks (Task 3-02 step 3, "retaining the
    ///   old producer during convergence").
    /// - `protectedMainPrivatePayload` — the private contract: requires
    ///   exactly `verification / workspace`. No compatibility variant
    ///   exists because no prior producer preceded it — Phase 2 is what
    ///   first gives private repositories any CI attestation at all.
    ///
    /// The `rulesets` job classifies each target repository mechanically
    /// (root `Package.swift` present ⇒ package; absent ⇒ control;
    /// `Policy/ruleset-class-overrides.json` wins over the mechanical
    /// probe — swift-institute/.github#200/#266) and, for the package
    /// class, reads live visibility to select among the three payloads
    /// above.
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
        /// The target public contract: exactly `ci / matrix / ci-ok`.
        public static func protectedMainPayload(from url: URL) throws -> Data {
            try protectedMainPackagePayload(
                from: url,
                requiredContexts: ["ci / matrix / ci-ok"]
            )
        }

        /// The migration-window public contract: both the layer wrapper's
        /// temporary `ci / ci-ok` aggregate and the universal chain's own
        /// `ci / matrix / ci-ok` aggregate, required together so a wave
        /// stays reversible while both producers exist (Task 3-02 step 3).
        ///
        /// This is the one payload class that may declare the programme
        /// bypass window (`BypassAllowance.instituteBotAlways`, below). It
        /// is still fail-closed: an empty list stays valid, the single
        /// authorized `swift-institute-bot` App actor is admitted by exact
        /// shape, and anything else — a second actor, a different
        /// `actor_type`, a different `actor_id`, or `bypass_mode:
        /// pull_request` — is rejected exactly as before.
        public static func protectedMainPublicCompatibilityPayload(from url: URL) throws -> Data {
            try protectedMainPackagePayload(
                from: url,
                requiredContexts: ["ci / ci-ok", "ci / matrix / ci-ok"],
                bypassAllowance: .instituteBotAlways
            )
        }

        /// What a payload class is permitted to declare in `bypass_actors`.
        ///
        /// `none` is the standing Institute contract and the default: no
        /// actor may bypass protected main, which is why admin merge and
        /// admin direct push both fail (verified live —
        /// `current_user_can_bypass: "never"`).
        ///
        /// `instituteBotAlways` additionally admits **exactly one** actor —
        /// the `swift-institute-bot` GitHub App (`Integration`, id
        /// `3543256`), in `always` mode — and nothing else. It exists for
        /// the bounded programme window in which the fleet's
        /// `.github/workflows/ci.yml` callers are converged by direct push
        /// (swift-institute/.github#276 Task 5-02, #282; Ruling R26
        /// supersedes R22.2; Ruling R28.1 selects the App over an
        /// organization-admin actor because it is narrower and is what lets
        /// the pushes happen inside Actions). `pull_request` mode is
        /// deliberately NOT admitted: it permits merging without review,
        /// which is a weakening of the review contract, while `always`
        /// permits the push this window actually needs.
        ///
        /// This is an admission of a named, authorized shape — not a
        /// relaxation of the guard. Every other payload class keeps `none`,
        /// and the window is closed by restoring the empty list in the
        /// policy file and reverting this allowance.
        public enum BypassAllowance {
            case none
            case instituteBotAlways
        }

        /// The private contract: exactly `verification / workspace`, the
        /// trusted control-plane receipt (Task 2-01/2-02,
        /// swift-institute/.github#253). No compatibility variant: no
        /// producer preceded it.
        public static func protectedMainPrivatePayload(from url: URL) throws -> Data {
            try protectedMainPackagePayload(
                from: url,
                requiredContexts: ["verification / workspace"]
            )
        }

        /// Shared package-class validator parameterized by the exact set of
        /// required contexts. `requiredContexts` is the Swift-side equality
        /// guard: it must match the JSON policy file's own
        /// `required_status_checks` contexts exactly (same cardinality, same
        /// set, no duplicates) or the payload is rejected — a one-sided
        /// Swift-only or JSON-only edit fails this guard.
        private static func protectedMainPackagePayload(
            from url: URL,
            requiredContexts: Set<String>,
            bypassAllowance: BypassAllowance = .none
        ) throws -> Data {
            let (object, rules) = try identity(
                from: url,
                expectedName: "Institute protected main",
                bypassAllowance: bypassAllowance
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
                required.count == requiredContexts.count,
                Set(required.compactMap { $0["context"] as? String }) == requiredContexts
            else {
                throw ConfigurationError(
                    "protected-main status-check transaction differs from the Institute contract"
                )
            }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }

        /// The control-plane variant: identical protections minus the
        /// required-status-check rule, since control-plane repositories emit
        /// neither `ci / matrix / ci-ok` nor `verification / workspace` —
        /// visibility is irrelevant to this class. Its rule-type set is
        /// exactly `deletion`,
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
            expectedName: String,
            bypassAllowance: BypassAllowance = .none
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
            guard let bypass = object["bypass_actors"] as? [Any] else {
                throw ConfigurationError("protected-main ruleset must declare bypass_actors")
            }
            try validateBypassActors(bypass, allowance: bypassAllowance)
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

        /// Fail-closed `bypass_actors` validation. An empty list is always
        /// valid. A non-empty list is valid ONLY under
        /// `.instituteBotAlways`, and only as exactly one entry whose three
        /// fields match the authorized shape exactly — an extra key, an
        /// extra actor, a different actor, or `pull_request` mode is
        /// rejected. The default remains "no bypass actor at all", so a
        /// payload class that does not opt in cannot acquire one by edit.
        private static func validateBypassActors(
            _ bypass: [Any],
            allowance: BypassAllowance
        ) throws {
            if bypass.isEmpty { return }
            guard case .instituteBotAlways = allowance else {
                throw ConfigurationError("protected-main ruleset permits a bypass actor")
            }
            guard bypass.count == 1, let actor = bypass[0] as? [String: Any],
                actor.count == 3,
                actor["actor_id"] as? Int == 3543256,
                actor["actor_type"] as? String == "Integration",
                actor["bypass_mode"] as? String == "always"
            else {
                throw ConfigurationError(
                    "protected-main ruleset declares a bypass actor outside the one authorized "
                        + "swift-institute-bot App always-mode window"
                )
            }
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
