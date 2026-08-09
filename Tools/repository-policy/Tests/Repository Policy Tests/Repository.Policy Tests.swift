import Foundation
import Repository_Policy
import Testing

@Suite
struct RepositoryPolicyTests {
    @Test
    func eligibilityFixtures() throws {
        let url = try #require(Bundle.module.url(forResource: "eligibility", withExtension: "json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))

        #expect(fixtures.count == 9)
        for fixture in fixtures {
            let state = fixture.pvr.flatMap(RepositoryPolicy.VulnerabilityReporting.init(rawValue:))
            let decision = RepositoryPolicy.decision(
                for: fixture.repository,
                manifestKind: fixture.manifestKind,
                vulnerabilityReporting: state
            )
            #expect(render(decision) == fixture.decision, "\(fixture.name)")
        }
    }

    @Test
    func scopeRejectsDeniedOwner() {
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(
                organization: nil,
                repository: "tenthijeboonkkamp/package"
            )
        }
    }

    @Test
    func scopeRequiresExactlyOneSelector() {
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(organization: nil, repository: nil)
        }
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Scope(
                organization: "swift-foundations",
                repository: "swift-foundations/swift-example"
            )
        }
    }

    @Test
    func protectedMainRulesetFixtureDefinesThePRTransaction() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        let payload = try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect((object["bypass_actors"] as? [Any])?.isEmpty == true)
        #expect((object["enforcement"] as? String) == "active")
        let rules = try #require(object["rules"] as? [[String: Any]])
        let review = try #require(
            rules.first(where: { $0["type"] as? String == "pull_request" })?["parameters"]
                as? [String: Any]
        )
        let checks = try #require(
            rules.first(where: { $0["type"] as? String == "required_status_checks" })?["parameters"]
                as? [String: Any]
        )
        // A bot's existing approval counts, but a pusher (including coenttb)
        // cannot approve its own last push; stale approvals are dismissed.
        #expect(review["required_approving_review_count"] as? Int == 1)
        #expect(review["require_last_push_approval"] as? Bool == true)
        #expect(review["dismiss_stale_reviews_on_push"] as? Bool == true)
        // GitHub's PR gate rejects unresolved conversations and a non-current
        // check; the caller-path-prefixed `ci / matrix / ci-ok` aggregate is
        // the one required current-head status, as rendered on live package
        // PR heads (renamed from `ci / ci-ok` — swift-institute/.github#276
        // Task 3-01).
        #expect(review["required_review_thread_resolution"] as? Bool == true)
        // GitHub server-canonicalizes allowed_merge_methods,
        // dismissal_restriction, and required_reviewers onto every
        // pull_request rule even when the contract omits them
        // (swift-institute/.github#196); the contract now pins all three
        // explicitly so the applied ruleset's read-back stays in exact
        // correspondence, and squash-only merge policy is an enforced fact
        // rather than an unpinned server default.
        #expect(review["allowed_merge_methods"] as? [String] == ["squash"])
        #expect((review["required_reviewers"] as? [Any])?.isEmpty == true)
        let dismissalRestriction = try #require(
            review["dismissal_restriction"] as? [String: Any]
        )
        #expect(dismissalRestriction["enabled"] as? Bool == false)
        #expect((dismissalRestriction["allowed_actors"] as? [Any])?.isEmpty == true)
        #expect(checks["strict_required_status_checks_policy"] as? Bool == true)
        let required = try #require(checks["required_status_checks"] as? [[String: Any]])
        #expect(required.count == 1)
        #expect(required.first?["context"] as? String == "ci / matrix / ci-ok")
    }

    // Positive control: the now-retired temporary compatibility context
    // `ci / ci-ok` is no longer, alone, the target public contract — a
    // payload requiring only it would gate main on a layer wrapper's
    // temporary aggregate that Task 3-02 step 7 deletes. The validator must
    // refuse it (swift-institute/.github#276 Task 3-01, renamed from the
    // bare-legacy-name positive control this replaces).
    @Test
    func protectedMainPayloadRejectsTheRetiredCompatibilityContextAlone() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        let legacy = try String(contentsOf: canonical, encoding: .utf8)
            .replacingOccurrences(
                of: "\"context\": \"ci / matrix / ci-ok\"",
                with: "\"context\": \"ci / ci-ok\""
            )
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try Data(legacy.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        }
    }

    // Positive control: the retired bare `ci-ok` context (no caller-path
    // prefix at all) is a name no caller path has ever rendered, so a
    // payload requiring it would gate main on a check that can never
    // report. The validator must refuse it.
    @Test
    func protectedMainPayloadRejectsTheBareUnprefixedContext() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        let legacy = try String(contentsOf: canonical, encoding: .utf8)
            .replacingOccurrences(
                of: "\"context\": \"ci / matrix / ci-ok\"",
                with: "\"context\": \"ci-ok\""
            )
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try Data(legacy.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        }
    }

    // MARK: - Bypass prohibition (TX5, swift-institute/.github#276)

    // Writes `object` to a scratch fixture and returns its URL. Used by the
    // bypass negative controls below, which need a payload that differs from
    // a shipped fixture in exactly one field.
    private func scratchFixture(_ object: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-bypass-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        return url
    }

    // Discriminating negative: no payload class admits a bypass actor. The
    // retired R28.1 programme window's actor (the swift-institute-bot App,
    // `always` mode) is refused on every class — the standing contract is
    // "no bypass actor at all".
    @Test
    func everyPayloadClassRefusesAnyBypassActor() throws {
        let authorized = [
            ["actor_id": 3543256, "actor_type": "Integration", "bypass_mode": "always"]
        ]
        for fixture in [
            "Policy/protected-main-ruleset.json",
            "Policy/protected-main-private-ruleset.json",
            "Policy/protected-main-control-ruleset.json",
        ] {
            let source = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: fixture)
            var object = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any]
            )
            object["bypass_actors"] = authorized
            let url = try scratchFixture(object)
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: RepositoryPolicy.ConfigurationError.self) {
                if fixture.contains("control") {
                    _ = try RepositoryPolicy.Ruleset.protectedMainControlPayload(from: url)
                } else if fixture.contains("private") {
                    _ = try RepositoryPolicy.Ruleset.protectedMainPrivatePayload(from: url)
                } else {
                    _ = try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
                }
            }
        }
    }

    // MARK: - Private ruleset contract (Task 2-01/2-02, #253; Task 3-01)

    // Positive control: the private fixture requires exactly `verification /
    // workspace` — the trusted control-plane receipt — and nothing else. No
    // compatibility variant exists: no producer preceded it.
    @Test
    func protectedMainPrivatePayloadFixtureRequiresWorkspaceVerification() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-private-ruleset.json")
        let payload = try RepositoryPolicy.Ruleset.protectedMainPrivatePayload(from: url)
        let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let rules = try #require(object["rules"] as? [[String: Any]])
        let checks = try #require(
            rules.first(where: { $0["type"] as? String == "required_status_checks" })?[
                "parameters"
            ] as? [String: Any]
        )
        let required = try #require(checks["required_status_checks"] as? [[String: Any]])
        #expect(required.count == 1)
        #expect(required.first?["context"] as? String == "verification / workspace")
    }

    // Discriminating negative: the private validator must refuse the public
    // final fixture (wrong context), and the public final validator must
    // refuse the private fixture — visibility selects a genuinely different
    // required context, not an interchangeable label.
    @Test
    func protectedMainPrivateAndPublicPayloadsRejectEachOthersFixture() throws {
        let publicFixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        let privateFixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-private-ruleset.json")
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPrivatePayload(from: publicFixture)
        }
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: privateFixture)
        }
    }

    // Positive control: a payload carrying a required-status-checks rule
    // missing entirely is refused by every package-class validator alike —
    // isolates the shared rule-completeness check from the per-variant
    // context-set check.
    @Test
    func everyPackageVariantRejectsAPayloadMissingTheRequiredStatusChecksRule() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: canonical)) as? [String: Any]
        )
        var rules = try #require(object["rules"] as? [[String: Any]])
        rules.removeAll { $0["type"] as? String == "required_status_checks" }
        object["rules"] = rules
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        }
        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPrivatePayload(from: url)
        }
    }

    // Positive control: GitHub's read-back carries additional top-level
    // server metadata (id, node_id, source_type, timestamps) the contract
    // never emits (swift-institute/.github#196). Once the pull_request
    // parameters carry the exact pinned shape, that additive metadata must
    // not fail validation — the read-back comparison in sync-metadata.yml's
    // `rulesets` job only needs the pinned fields, not byte-identical
    // top-level shape.
    @Test
    func protectedMainPayloadAcceptsACanonicalReadbackAroundThePinnedContract() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: canonical)) as? [String: Any]
        )
        object["id"] = 20_244_631
        object["node_id"] = "RUL_lADummyReadback"
        object["source_type"] = "Repository"
        object["created_at"] = "2026-08-02T00:00:00Z"
        object["updated_at"] = "2026-08-02T00:00:00Z"
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        let decoded = try #require(
            try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        let rules = try #require(decoded["rules"] as? [[String: Any]])
        let review = try #require(
            rules.first(where: { $0["type"] as? String == "pull_request" })?["parameters"]
                as? [String: Any]
        )
        #expect(review["allowed_merge_methods"] as? [String] == ["squash"])
    }

    // Discriminating negative: GitHub's server-default merge-method set —
    // all three methods — must be rejected. Institute policy is
    // squash-only; a contract or read-back carrying the wider set is a
    // policy weakening (swift-institute/.github#196), not normalization
    // drift, so it must fail closed rather than pass as "close enough".
    @Test
    func protectedMainPayloadRejectsAllMergeMethods() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        let allMethods = try String(contentsOf: canonical, encoding: .utf8)
            .replacingOccurrences(
                of: "\"allowed_merge_methods\": [\"squash\"]",
                with: "\"allowed_merge_methods\": [\"merge\", \"squash\", \"rebase\"]"
            )
        #expect(allMethods.contains("\"merge\", \"squash\", \"rebase\""))
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try Data(allMethods.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        }
    }

    // Discriminating negative: the pre-fix contract shape — silent on
    // allowed_merge_methods, dismissal_restriction, and required_reviewers —
    // must be rejected going forward (swift-institute/.github#196), even
    // though GitHub itself accepts it and silently canonicalizes a weaker
    // merge-method default over it.
    @Test
    func protectedMainPayloadRejectsAnUnpinnedMergeMethodContract() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        let unpinned =
            try String(contentsOf: canonical, encoding: .utf8)
            .replacingOccurrences(of: "\"allowed_merge_methods\": [\"squash\"], ", with: "")
            .replacingOccurrences(
                of: "\"dismissal_restriction\": { \"allowed_actors\": [], \"enabled\": false }, ",
                with: ""
            )
            .replacingOccurrences(of: ", \"required_reviewers\": []", with: "")
        // Confirm the substitution actually reproduces the pre-fix shape
        // before asserting on the validator's behavior against it.
        #expect(!unpinned.contains("allowed_merge_methods"))
        #expect(!unpinned.contains("dismissal_restriction"))
        #expect(!unpinned.contains("required_reviewers"))
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try Data(unpinned.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        }
    }

    // MARK: - Control-plane ruleset contract (swift-institute/.github#200)

    // Positive control: the shipped control-plane fixture is exactly three
    // rules (deletion, non_fast_forward, pull_request), carries no
    // required_status_checks rule at all, and pins the identical
    // pull-request transaction as the package contract.
    @Test
    func protectedMainControlPayloadFixtureDefinesTheControlPlaneTransaction() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-control-ruleset.json")
        let payload = try RepositoryPolicy.Ruleset.protectedMainControlPayload(from: url)
        let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect((object["name"] as? String) == "Institute protected main (control)")
        #expect((object["bypass_actors"] as? [Any])?.isEmpty == true)
        #expect((object["enforcement"] as? String) == "active")
        let rules = try #require(object["rules"] as? [[String: Any]])
        #expect(
            Set(rules.compactMap { $0["type"] as? String })
                == ["deletion", "non_fast_forward", "pull_request"]
        )
        #expect(!rules.contains { $0["type"] as? String == "required_status_checks" })
        let review = try #require(
            rules.first(where: { $0["type"] as? String == "pull_request" })?["parameters"]
                as? [String: Any]
        )
        #expect(review["required_approving_review_count"] as? Int == 1)
        #expect(review["require_last_push_approval"] as? Bool == true)
        #expect(review["dismiss_stale_reviews_on_push"] as? Bool == true)
        #expect(review["required_review_thread_resolution"] as? Bool == true)
        #expect(review["allowed_merge_methods"] as? [String] == ["squash"])
        #expect((review["required_reviewers"] as? [Any])?.isEmpty == true)
    }

    // Discriminating negative: a package contract missing its
    // required_status_checks rule (name unchanged) must still be refused —
    // isolates the rule-completeness check from the name/identity check.
    @Test
    func protectedMainPayloadRejectsAPayloadMissingTheRequiredStatusChecksRule() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: canonical)) as? [String: Any]
        )
        var rules = try #require(object["rules"] as? [[String: Any]])
        rules.removeAll { $0["type"] as? String == "required_status_checks" }
        object["rules"] = rules
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-ruleset-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: url)
        }
    }

    // Discriminating negative: a control contract carrying a smuggled
    // required_status_checks rule (name unchanged) must be refused — the
    // control contract's rule-type set admits exactly three rules.
    @Test
    func protectedMainControlPayloadRejectsASmuggledRequiredStatusChecksRule() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-control-ruleset.json")
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: canonical)) as? [String: Any]
        )
        var rules = try #require(object["rules"] as? [[String: Any]])
        rules.append([
            "type": "required_status_checks",
            "parameters": [
                "do_not_enforce_on_create": false,
                "required_status_checks": [["context": "ci / ci-ok"]],
                "strict_required_status_checks_policy": true,
            ],
        ])
        object["rules"] = rules
        let url = FileManager.default.temporaryDirectory
            .appending(path: "protected-main-control-ruleset-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainControlPayload(from: url)
        }
    }

    // Cross-validation: the control validator must refuse the real package
    // payload (wrong name, and a required_status_checks rule the control
    // rule-type set does not admit).
    @Test
    func protectedMainControlPayloadRejectsTheRealPackagePayload() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-ruleset.json")

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainControlPayload(from: canonical)
        }
    }

    // Cross-validation: the package validator must refuse the real control
    // payload (wrong name, and no required_status_checks rule at all).
    @Test
    func protectedMainPayloadRejectsTheRealControlPayload() throws {
        let canonical = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Policy/protected-main-control-ruleset.json")

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.Ruleset.protectedMainPayload(from: canonical)
        }
    }

    @Test
    func `ruleset org enumerator excludes forks`() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/sync-metadata.yml")
        let workflow = try String(contentsOf: url, encoding: .utf8)
        let rulesets = try #require(workflow.range(of: "\n  rulesets:\n"))
        let enumerator = try #require(
            workflow.range(
                of: "      - name: Enumerate org repos\n",
                range: rulesets.upperBound..<workflow.endIndex
            )
        )
        let converge = try #require(
            workflow.range(
                of: "      - name: Converge protected main ruleset\n",
                range: enumerator.upperBound..<workflow.endIndex
            )
        )
        let inputs = workflow[enumerator.upperBound..<converge.lowerBound]

        #expect(inputs.contains("\n          exclude-forks: 'true'\n"))
    }

    // MARK: - Ruleset sweep convergence (swift-institute/.github#204)

    // Positive: an Institute ruleset that already exists is always
    // re-applied, under either sweep posture — the nightly's scheduled-heal
    // mode heals drift exactly like the explicit-apply mode does.
    @Test
    func decideConvergenceReappliesAnExistingRulesetUnderEitherMode() {
        for mode: RepositoryPolicy.Ruleset.SweepMode in [.scheduledHeal, .explicitApply] {
            let decision = RepositoryPolicy.Ruleset.decideConvergence(
                rulesetExists: true,
                mode: mode
            )
            #expect(decision.action == .reapply, "\(mode)")
        }
    }

    // Positive: an absent ruleset under the explicit apply-rulesets opt-in
    // still creates — the swift-institute/.github#193 first-application
    // path is unchanged by #204.
    @Test
    func decideConvergenceCreatesAnAbsentRulesetUnderExplicitApply() {
        let decision = RepositoryPolicy.Ruleset.decideConvergence(
            rulesetExists: false,
            mode: .explicitApply
        )
        #expect(decision.action == .create)
    }

    // Discriminating negative: an absent ruleset under the nightly's
    // scheduled-heal posture is skipped, never created — first application
    // on a previously unenforced repository stays excluded from the
    // scheduled path (explicit opt-in only).
    @Test
    func decideConvergenceSkipsAnAbsentRulesetUnderScheduledHeal() {
        let decision = RepositoryPolicy.Ruleset.decideConvergence(
            rulesetExists: false,
            mode: .scheduledHeal
        )
        #expect(decision.action == .skipAbsentOnSchedule)
        #expect(decision.reason.contains("explicit opt-in only"))
    }

    // The nightly caller must actually opt in to heal-only convergence, and
    // must not also opt into the create-capable explicit-apply path — the
    // scheduled path stays limited to healing existing rulesets
    // (swift-institute/.github#204).
    @Test
    func nightlySweepEnablesHealRulesetsAndNotApplyRulesets() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/sync-metadata-nightly.yml")
        let workflow = try String(contentsOf: url, encoding: .utf8)
        let sweep = try #require(workflow.range(of: "\n  sweep:\n"))
        let report = try #require(
            workflow.range(of: "\n  report:\n", range: sweep.upperBound..<workflow.endIndex)
        )
        let sweepJob = workflow[sweep.upperBound..<report.lowerBound]

        #expect(sweepJob.contains("\n      heal-rulesets: true\n"))
        #expect(sweepJob.contains("\n      visibility: all\n"))
        // Only the mapping key is forbidden (an explanatory comment
        // mentioning apply-rulesets is fine); the sweep must not pass it.
        #expect(!sweepJob.contains("\n      apply-rulesets:"))
    }

    // The `rulesets` job must run on either explicit opt-in, and the
    // per-target convergence step must route the heal-vs-skip-absent
    // decision through the Swift tool rather than re-deciding it in bash.
    @Test
    func rulesetsJobGatesOnEitherOptInAndDelegatesTheConvergenceDecision() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/sync-metadata.yml")
        let workflow = try String(contentsOf: url, encoding: .utf8)
        let rulesets = try #require(workflow.range(of: "\n  rulesets:\n"))
        let surfaces = try #require(
            workflow.range(of: "\n  surfaces:\n", range: rulesets.upperBound..<workflow.endIndex)
        )
        let rulesetsJob = workflow[rulesets.upperBound..<surfaces.lowerBound]

        #expect(
            rulesetsJob.contains(
                "if: ${{ !github.event.repository.private && (inputs.apply-rulesets || inputs.heal-rulesets) }}"
            )
        )
        #expect(rulesetsJob.contains("repository-policy ruleset-convergence"))
        #expect(rulesetsJob.contains("skipAbsentOnSchedule"))

        // Both input blocks (workflow_call and workflow_dispatch) declare
        // heal-rulesets, defaulted false so an ad hoc dispatch is unaffected
        // unless it opts in explicitly.
        let onBlock = try #require(workflow.range(of: "\non:\n", range: workflow.startIndex..<rulesets.lowerBound))
        let inputsText = workflow[onBlock.upperBound..<rulesets.lowerBound]
        #expect(inputsText.components(separatedBy: "heal-rulesets:").count - 1 == 2)
    }

    // MARK: - Visibility-aware required-check payload selection (Task 3-01)

    // Positive control: the `rulesets` job reads a target's visibility live
    // from GitHub rather than consulting any declared policy file, computes
    // all three package-adjacent payloads, and fails closed (`::error::` +
    // `exit 1`, never a silent default) when visibility is neither `public`
    // nor `private`.
    @Test
    func rulesetsJobReadsVisibilityLiveAndFailsClosedOnAnUnrecognizedValue() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/sync-metadata.yml")
        let workflow = try String(contentsOf: url, encoding: .utf8)
        let sync = try #require(workflow.range(of: "\n  sync:\n"))
        let privateCallers = try #require(workflow.range(of: "\n  private-callers:\n"))
        let rulesets = try #require(workflow.range(of: "\n  rulesets:\n"))
        let surfaces = try #require(
            workflow.range(of: "\n  surfaces:\n", range: rulesets.upperBound..<workflow.endIndex)
        )
        let rulesetsJob = workflow[rulesets.upperBound..<surfaces.lowerBound]
        let syncJob = workflow[sync.upperBound..<privateCallers.lowerBound]

        // Metadata and merge-method convergence follows the caller's full
        // visibility scope. Rulesets stay public-only because the current
        // plan refuses their API on private repositories.
        #expect(syncJob.contains("visibility: ${{ inputs.visibility }}"))
        #expect(syncJob.contains("INPUT_VISIBILITY: ${{ inputs.visibility }}"))
        #expect(rulesetsJob.contains("visibility: public"))
        #expect(rulesetsJob.contains("INPUT_VISIBILITY: public"))

        // Live read, not a declared list.
        #expect(rulesetsJob.contains(#"gh api "repos/$target" --jq '.visibility'"#))
        // The package-adjacent payloads are all computed up front (TX5
        // retired the migration-window compatibility payload).
        #expect(rulesetsJob.contains("desired_package_public="))
        #expect(!rulesetsJob.contains("desired_package_public_compat="))
        #expect(rulesetsJob.contains("desired_package_private="))
        // Fail-closed branch: neither public nor private is UNMEASURED, not
        // a default.
        #expect(rulesetsJob.contains("*)"))
        #expect(
            rulesetsJob.contains(
                "UNMEASURED — visibility '${target_visibility}' is neither 'public' nor 'private'"
            )
        )
    }

    // The public metadata workflow may converge private targets during the
    // nightly all-visibility sweep. The cohort crosses steps only through an
    // opaque runner-local file path, and private targets are represented only
    // by in-run ordinals in logs and summaries.
    @Test
    func syncJobKeepsPrivateTargetCoordinatesOutOfPublicReporting() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/sync-metadata.yml")
        let workflow = try String(contentsOf: url, encoding: .utf8)
        let enumeration = try String(
            contentsOf: url
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "actions/enumerate-org-public-repos/action.yml"),
            encoding: .utf8
        )
        let sync = try #require(workflow.range(of: "\n  sync:\n"))
        let privateCallers = try #require(workflow.range(of: "\n  private-callers:\n"))
        let rulesets = try #require(workflow.range(of: "\n  rulesets:\n"))
        let syncJob = workflow[sync.upperBound..<privateCallers.lowerBound]
        let callerJob = workflow[privateCallers.upperBound..<rulesets.lowerBound]

        #expect(syncJob.contains("ENUM_REPOS_FILE: ${{ steps.enum.outputs.repos-file }}"))
        #expect(syncJob.contains("done < \"$ENUM_REPOS_FILE\""))
        #expect(!syncJob.contains("ENUM_REPOS: ${{ steps.enum.outputs.repos }}"))
        #expect(callerJob.contains("converge-approval-callers"))
        #expect(callerJob.contains("--targets-file \"${{ steps.enum.outputs.repos-file }}\""))
        #expect(!callerJob.contains("outputs.repos }}"))
        #expect(!callerJob.contains("for target in"))
        #expect(callerJob.contains("permission-contents: write"))
        #expect(callerJob.contains("permission-metadata: read"))
        #expect(callerJob.contains("permission-pull-requests: write"))
        #expect(!callerJob.contains("permission-administration:"))
        #expect(!callerJob.contains("permission-actions:"))
        #expect(!callerJob.contains("repositories:"))
        #expect(enumeration.contains("echo \"repos-file=${repos_file}\""))
        #expect(enumeration.contains("if [[ \"$VISIBILITY\" == \"public\" ]]; then"))
        #expect(enumeration.contains("> \"$repos_file\""))

        // Positive control: public repositories retain their actionable name.
        #expect(syncJob.contains("if [[ \"$target_visibility\" == \"public\" ]]; then"))
        #expect(syncJob.contains("reported_target=\"$target\""))
        #expect(syncJob.contains("printf '    gh repo edit %q' \"$target\""))

        // Negative controls cover ordinary reporting, dry-run command
        // previews, fatal failures, and summary generation. The ordinal is
        // intentionally not derived from or correlated with the coordinate.
        #expect(syncJob.contains("reported_target=\"target #${target_ordinal}\""))
        #expect(syncJob.contains("echo \"    ${reported_target}: mutation preview suppressed\""))
        #expect(syncJob.contains("echo \"::error::${reported_target}: could not read repository visibility.\""))
        #expect(syncJob.contains("summary_lines+=(\"- \\`${reported_target}\\`: ${repo_diffs} field(s) — dry-run preview\")"))
        #expect(syncJob.contains("summary_lines+=(\"- \\`${reported_target}\\`: ${repo_diffs} field(s) applied\")"))
        #expect(!syncJob.contains("echo \"  ${target}:"))
        #expect(!syncJob.contains("::error::${target}"))
        #expect(!syncJob.contains("summary_lines+=(\"- \\`${target}\\`:"))
    }

    @Test
    func botReviewTransactionSourcesCollectionsFromFiles() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".github/workflows/review-pr-transaction-core.yml")
        let workflow = try String(contentsOf: url, encoding: .utf8)

        for payload in ["reviews", "checks", "runs", "graph"] {
            #expect(workflow.contains("--slurpfile \(payload)"), "\(payload) must be file-backed")
            #expect(!workflow.contains("--argjson \(payload)"), "\(payload) must not enter argv")
        }
        #expect(workflow.contains("accepted-plan:"))
        #expect(workflow.contains("timelineItems(itemTypes: [CROSS_REFERENCED_EVENT]"))
        // The transaction engine admits every owning-issue type it is
        // authorized against (swift-institute/.github#199, #201, #294); pin
        // all four comparisons, not just the first, so a future edit cannot
        // silently narrow the admitted set back down without failing here.
        // Spelled in the jq form introduced by #294
        // (`.issueType.name as $t | ($t == "Task" or ...)`).
        #expect(workflow.contains("issueType.name as $t"))
        #expect(workflow.contains("$t == \"Task\""))
        #expect(workflow.contains("$t == \"Bug\""))
        #expect(workflow.contains("$t == \"Feature\""))
        #expect(workflow.contains("$t == \"Goal\""))
        #expect(!workflow.contains("closingIssuesReferences"))
        #expect(!workflow.contains(".number == 176"))

        let parse = try #require(workflow.range(of: "- name: Resolve trusted caller route"))
        let mint = try #require(workflow.range(of: "- name: Mint narrowed reviewer token"))
        let resolve = try #require(workflow.range(of: "- name: Resolve exact target scope"))
        #expect(parse.lowerBound < mint.lowerBound)
        #expect(mint.lowerBound < resolve.lowerBound)
        #expect(workflow.contains("GH_TOKEN: ${{ steps.token.outputs.token }}"))
        #expect(workflow.contains("permission-actions: read"))
        #expect(workflow.contains("permission-checks: read"))
        #expect(workflow.contains("permission-issues: read"))
        #expect(workflow.contains("repositories: ${{ steps.target.outputs.name }}"))
        #expect(workflow.contains("id: .id"))
        #expect(workflow.contains("attempt: .run_attempt"))
        #expect(workflow.contains("startedAt: .run_started_at"))
        #expect(workflow.contains(#"select(.visibility == env.TARGET_VISIBILITY)"#))
        #expect(workflow.contains("TARGET_REPOSITORY=\"$CALLER_REPOSITORY\""))
        #expect(workflow.contains("CALLER_WORKFLOW_REF: ${{ github.workflow_ref }}"))
        #expect(workflow.contains("permission-pull-requests: write"))
        #expect(!workflow.contains("permission-administration:"))
        #expect(!workflow.contains("permission-workflows:"))
    }

    @Test
    func `private review caller keeps identity and plan on the private route`() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let publicCaller = try String(
            contentsOf: root.appending(path: ".github/workflows/review-pr-transaction.yml"),
            encoding: .utf8
        )
        let privateCaller = try String(
            contentsOf: root.appending(path: "canon/review-pr-transaction-private.yml"),
            encoding: .utf8
        )

        #expect(publicCaller.contains("route: public"))
        #expect(publicCaller.contains("repository: ${{ inputs.repository }}"))
        #expect(!publicCaller.contains("route: private"))

        #expect(privateCaller.contains("github.event.repository.private"))
        #expect(privateCaller.contains("route: private"))
        #expect(privateCaller.contains("accepted-plan: ${{ inputs.accepted-plan }}"))
        #expect(!privateCaller.contains("repository: ${{ inputs.repository }}"))
        #expect(!privateCaller.contains("repository:\n"))
        #expect(privateCaller.contains("review-pr-transaction-core.yml@main"))
        #expect(privateCaller.contains("SWIFT_INSTITUTE_BOT_APP_PRIVATE_KEY"))
        #expect(!privateCaller.contains("secrets: inherit"))
    }

    @Test
    func surfacePolicyAcceptsWhitelistedThinCaller() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on:
                  push:
                  pull_request:
                  workflow_dispatch:
                jobs:
                  ci:
                    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["pull_request", "push", "workflow_dispatch"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(report.passed)
        #expect(report.actionFiles == 1)
        #expect(report.issueFormFiles == 0)
    }

    // Regression for the nightly org-scope sweep false positive: `branches:`
    // and `tags:` are filter keys nested under `push:`/`pull_request:`, not
    // sibling trigger names, and must never be flattened into the scanned
    // `triggers` set alongside them.
    @Test
    func surfacePolicyIgnoresBranchAndTagFiltersNestedUnderATrigger() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on:
                  push:
                    branches: [main]
                    tags: ['v*']
                  pull_request:
                    branches: [main]
                  workflow_dispatch:
                jobs:
                  ci:
                    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["pull_request", "push", "workflow_dispatch"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(report.passed)
        #expect(report.violations.isEmpty)
    }

    @Test
    func surfacePolicyRejectsUnlistedTriggerUseAndInlineJob() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on:
                  schedule:
                    - cron: "0 4 * * *"
                jobs:
                  ci:
                    runs-on: ubuntu-latest
                    steps:
                      - uses: actions/checkout@v7
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["push"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(
            Set(report.violations.map(\.identifier))
                == ["REPO-ACTIONS-003", "REPO-ACTIONS-004", "REPO-ACTIONS-005"]
        )
    }

    @Test
    func surfacePolicyAcceptsExplicitToolOwnedWorkflowAndAction() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/lint.yml": """
                name: Lint
                on:
                  workflow_call:
                jobs:
                  lint:
                    runs-on: ubuntu-latest
                    steps:
                      - uses: ./.github/actions/install
                """,
                ".github/actions/install/action.yml": """
                name: Install
                description: Install the tool
                runs:
                  using: composite
                  steps:
                    - uses: actions/checkout@v7
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-linter",
            repositoryClass: .tool,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .tool,
                        repository: "swift-foundations/swift-linter",
                        path: ".github/workflows/lint.yml",
                        kind: .toolWorkflow,
                        triggers: ["workflow_call"],
                        uses: ["./.github/actions/install"]
                    ),
                    .init(
                        repositoryClass: .tool,
                        repository: "swift-foundations/swift-linter",
                        path: ".github/actions/install/action.yml",
                        kind: .toolAction,
                        triggers: [],
                        uses: ["actions/checkout@v7"]
                    ),
                ],
                exemptions: []
            )
        )

        #expect(report.passed)
        #expect(report.actionFiles == 2)
    }

    @Test
    func surfacePolicyDeniesLocalIssueFormsAndHonorsExactTypedExemptions() throws {
        let root = try repositoryFixture(
            files: [
                ".github/workflows/recovery.yml": """
                name: Recovery
                on: workflow_dispatch
                jobs:
                  recover:
                    runs-on: ubuntu-latest
                    steps:
                      - uses: actions/checkout@v7
                """,
                ".github/ISSUE_TEMPLATE/bug.yml": "name: Bug\n",
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let denied = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )
        #expect(
            Set(denied.violations.map(\.identifier))
                == ["REPO-ACTIONS-001", "REPO-FORMS-001"]
        )

        let exempted = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(
                schemaVersion: 1,
                actionGrants: [],
                exemptions: [
                    .init(
                        surface: .actions,
                        repository: "swift-foundations/swift-example",
                        path: ".github/workflows/recovery.yml",
                        reason: "bounded recovery until the central operation lands"
                    ),
                    .init(
                        surface: .issueForms,
                        repository: "swift-foundations/swift-example",
                        path: ".github/ISSUE_TEMPLATE/bug.yml",
                        reason: "repository requires a typed form unavailable at organization scope"
                    ),
                ]
            )
        )
        #expect(exempted.passed)
        #expect(exempted.exemptionsApplied == 2)
    }

    @Test
    func remoteSurfaceSnapshotUsesTheSameTypedPolicy() throws {
        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on: [push, pull_request]
                jobs:
                  ci:
                    uses: swift-foundations/.github/.github/workflows/swift-ci.yml@main
                """,
                ".github/ISSUE_TEMPLATE/bug.yml": "name: Bug\n",
                "Sources/Example.swift": "public struct Example {}\n",
            ],
            policy: .init(
                schemaVersion: 1,
                actionGrants: [
                    .init(
                        repositoryClass: .package,
                        path: ".github/workflows/ci.yml",
                        kind: .thinCaller,
                        triggers: ["pull_request", "push"],
                        uses: [
                            "swift-foundations/.github/.github/workflows/swift-ci.yml@main"
                        ]
                    )
                ],
                exemptions: []
            )
        )

        #expect(report.actionFiles == 1)
        #expect(report.issueFormFiles == 1)
        #expect(report.violations.map(\.identifier) == ["REPO-FORMS-001"])
    }

    @Test
    func instituteDefaultSurfacePolicyMatchesTheDesignedFleet() throws {
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: RepositoryPolicy.SurfacePolicy.instituteDefaultURL
        )

        #expect(policy.schemaVersion == 1)

        // The generic package thin-caller grant admits exactly the designed
        // `uses:` targets: the three layer swift-ci and swift-docs wrappers,
        // plus the notify-linter-republish reusable the rule-pack repositories
        // call on push to main.
        let generic = try #require(
            policy.actionGrants.first {
                $0.repository == nil && $0.path == ".github/workflows/ci.yml"
            }
        )
        #expect(generic.repositoryClass == .package)
        #expect(generic.kind == .thinCaller)
        #expect(generic.triggers == ["pull_request", "push", "workflow_dispatch"])
        #expect(
            generic.uses == [
                "swift-foundations/.github/.github/workflows/swift-ci.yml@main",
                "swift-foundations/.github/.github/workflows/swift-docs.yml@main",
                "swift-institute/.github/.github/workflows/notify-linter-republish.yml@main",
                "swift-primitives/.github/.github/workflows/swift-ci.yml@main",
                "swift-primitives/.github/.github/workflows/swift-docs.yml@main",
                "swift-standards/.github/.github/workflows/swift-ci.yml@main",
                "swift-standards/.github/.github/workflows/swift-docs.yml@main",
            ]
        )

        let privateReview = try #require(
            policy.actionGrants.first {
                $0.repository == nil
                    && $0.path == ".github/workflows/review-pr-transaction.yml"
            }
        )
        #expect(privateReview.repositoryClass == .package)
        #expect(privateReview.kind == .thinCaller)
        #expect(privateReview.triggers == ["workflow_dispatch"])
        #expect(
            privateReview.uses == [
                "swift-institute/.github/.github/workflows/review-pr-transaction-core.yml@main"
            ]
        )

        // swift-linter is the tool-host: repository-scoped grants for its own
        // thin caller and its workflow_call reusable, nothing broader.
        let linterGrants = policy.actionGrants.filter {
            $0.repository == "swift-foundations/swift-linter"
        }
        #expect(linterGrants.count == 2)
        #expect(linterGrants.allSatisfy { $0.repositoryClass == .tool })
        #expect(
            linterGrants.first { $0.path == ".github/workflows/lint.yml" }?.kind
                == .toolWorkflow
        )

        // swift-institute/Issues (#266 follow-up): control-plane class, a
        // bespoke-kind grant naming exactly its own repository/path so it
        // never widens any other repository's admissible shape.
        let issuesGrants = policy.actionGrants.filter {
            $0.repository == "swift-institute/Issues"
        }
        #expect(issuesGrants.count == 1)
        let issuesGrant = try #require(issuesGrants.first)
        #expect(issuesGrant.repositoryClass == .controlPlane)
        #expect(issuesGrant.path == ".github/workflows/ci.yml")
        #expect(issuesGrant.kind == .bespoke)
        #expect(
            issuesGrant.triggers == ["pull_request", "push", "schedule", "workflow_dispatch"]
        )
        #expect(
            issuesGrant.uses == [
                "actions/checkout@v6",
                "swift-institute/.github/.github/workflows/swift-ci.yml@main",
            ]
        )

        // swift-institute/swift-institute.org (#276 predicate-18, decided
        // together with the same-day ruleset-class-overrides.json
        // reclassification): control-plane class, a bespoke-kind grant
        // naming exactly its own repository/path for its non-reusable
        // GitHub Pages deployment workflow.
        let siteGrants = policy.actionGrants.filter {
            $0.repository == "swift-institute/swift-institute.org"
        }
        #expect(siteGrants.count == 1)
        let siteGrant = try #require(siteGrants.first)
        #expect(siteGrant.repositoryClass == .controlPlane)
        #expect(siteGrant.path == ".github/workflows/deploy-docs.yml")
        #expect(siteGrant.kind == .bespoke)
        #expect(siteGrant.triggers == ["push", "workflow_dispatch"])
        #expect(
            siteGrant.uses == [
                "actions/checkout@v7",
                "actions/configure-pages@v6",
                "actions/deploy-pages@v5",
                "actions/upload-pages-artifact@v5",
                "swift-actions/setup-swift@v3",
            ]
        )

        #expect(policy.actionGrants.count == 6)

        // Typed exemptions carry exact repository and path scope.
        #expect(
            policy.exemptions.map { "\($0.repository):\($0.path)" }.sorted() == [
                "swift-foundations/swift-linter:.github/workflows/publish-ci-binaries.yml",
                "swift-foundations/swift-pdf:.github/workflows/windows-6.4-proof.yml",
                "swift-foundations/swift-pdf:.github/workflows/windows-existential-repro.yml",
                "swift-iso/swift-iso-32000:.github/workflows/no-verbatim-spec-text.yml",
            ]
        )
        #expect(policy.exemptions.allSatisfy { $0.surface == .actions })
    }

    // Positive control: the shipped policy must still DENY. A whitelist whose
    // gate has never been observed to fire is evidence of nothing, so these
    // fixtures are deliberately non-conformant and the check must flag them.
    @Test
    func instituteDefaultSurfacePolicyStillFiresOnNonConformantFixtures() throws {
        let policy = try RepositoryPolicy.SurfacePolicy.load(
            from: RepositoryPolicy.SurfacePolicy.instituteDefaultURL
        )

        // A sha-pinned wrapper ref cannot match the granted `@main` string.
        let shaPinned = try RepositoryPolicy.validateSurface(
            repository: "swift-primitives/swift-example",
            repositoryClass: .package,
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on: [push, pull_request, workflow_dispatch]
                jobs:
                  ci:
                    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@0123456789abcdef0123456789abcdef01234567
                """
            ],
            policy: policy
        )
        #expect(shaPinned.violations.map(\.identifier) == ["REPO-ACTIONS-004"])

        // The swift-pdf Windows-ICE exemption is repository-exact: the same
        // path in any other repository stays denied.
        let windowsFile = """
            name: Windows 6.4 proof
            on: [push, workflow_dispatch]
            jobs:
              proof:
                runs-on: windows-2022
                steps:
                  - uses: actions/checkout@v7
            """
        let wrongRepository = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            files: [".github/workflows/windows-6.4-proof.yml": windowsFile],
            policy: policy
        )
        #expect(wrongRepository.violations.map(\.identifier) == ["REPO-ACTIONS-001"])
        let exemptedRepository = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-pdf",
            repositoryClass: .package,
            files: [".github/workflows/windows-6.4-proof.yml": windowsFile],
            policy: policy
        )
        #expect(exemptedRepository.passed)
        #expect(exemptedRepository.exemptionsApplied == 1)

        // The admitted rule-pack shape passes: layer wrapper plus the
        // notify-linter-republish target in one thin caller.
        let rulePack = try RepositoryPolicy.validateSurface(
            repository: "swift-primitives/swift-linter-primitives",
            repositoryClass: .package,
            files: [
                ".github/workflows/ci.yml": """
                name: CI
                on: [push, pull_request, workflow_dispatch]
                jobs:
                  ci:
                    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
                  notify:
                    uses: swift-institute/.github/.github/workflows/notify-linter-republish.yml@main
                """
            ],
            policy: policy
        )
        #expect(rulePack.passed)
    }

    // The `reviewAfter` key was removed from the exemption schema
    // ([swift-institute/.github#110]) because it was decoded but read
    // nowhere. Load-time validation must reject any stray occurrence of it
    // (or any other unrecognized key) so the schema and the decoder stay in
    // exact correspondence going forward.
    @Test
    func surfacePolicyRejectsUnknownExemptionKeys() throws {
        let json = """
            {
              "schemaVersion": 1,
              "actionGrants": [],
              "exemptions": [
                {
                  "surface": "actions",
                  "repository": "swift-primitives/swift-example",
                  "path": ".github/workflows/legacy.yml",
                  "reason": "fixture",
                  "reviewAfter": "2026-01-01"
                }
              ]
            }
            """
        let url = FileManager.default.temporaryDirectory
            .appending(path: "repository-surfaces-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RepositoryPolicy.ConfigurationError.self) {
            try RepositoryPolicy.SurfacePolicy.load(from: url)
        }
    }

    // MARK: - REPO-DOCS-001 (SPI publish gate over placeholder DocC catalogues)

    // Positive: `.spi.yml` at the root plus a `.docc` markdown file that still
    // carries the umbrella placeholder marker produces exactly one
    // REPO-DOCS-001 advisory, and the advisory channel does not fail `passed`.
    @Test
    func docsPlaceholderAdvisoryFiresWhenSPIYMLPublishesAMarkedCatalogue() throws {
        let root = try repositoryFixture(
            files: [
                ".spi.yml": "version: 1\n",
                "Sources/Example/Example.docc/Example.md": """
                # ``Example``

                This is the umbrella catalog placeholder. Replace this line with a one-sentence \
                summary of the module.
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.map(\.identifier) == ["REPO-DOCS-001"])
        #expect(report.advisories.first?.path == "Sources/Example/Example.docc/Example.md")
        #expect(report.passed)
    }

    // Negative: `.spi.yml` present, but the catalogue has been completed (the
    // marker is gone) — no advisory.
    @Test
    func docsPlaceholderAdvisoryIsSilentOnACompletedCatalogue() throws {
        let root = try repositoryFixture(
            files: [
                ".spi.yml": "version: 1\n",
                "Sources/Example/Example.docc/Example.md": """
                # ``Example``

                Example provides a typed configuration surface for the repository policy tool.
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // Edge/fail-closed: a marked catalogue with no `.spi.yml` at the root is
    // not publication-gated — no advisory. The gate is about publication,
    // not about placeholders in general.
    @Test
    func docsPlaceholderAdvisoryIsSilentWithoutSPIYML() throws {
        let root = try repositoryFixture(
            files: [
                "Sources/Example/Example.docc/Example.md": """
                # ``Example``

                This is the umbrella catalog placeholder. Replace this line with a one-sentence \
                summary of the module.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // MARK: - REPO-README-001 / REPO-README-002 (struck badge, struck platform matrix)

    // Positive: a development-status badge image in root README.md produces
    // exactly one REPO-README-001 advisory, and only that identifier.
    @Test
    func readmeAdvisoryFiresOnDevelopmentStatusBadge() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                ![Status](https://img.shields.io/badge/status-active--development-blue.svg)

                Example is a typed configuration surface.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.map(\.identifier) == ["REPO-README-001"])
        #expect(report.passed)
    }

    // Positive: a `## Platform Support` heading in root README.md produces
    // exactly one REPO-README-002 advisory, and only that identifier.
    @Test
    func readmeAdvisoryFiresOnPlatformSupportHeading() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                ## Platform Support

                | Platform | Minimum |
                | --- | --- |
                | macOS | 15 |
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.map(\.identifier) == ["REPO-README-002"])
        #expect(report.passed)
    }

    // Negative: a converted README carrying neither construct — no advisory
    // from either identifier.
    @Test
    func readmeAdvisoriesAreSilentOnAConvertedREADME() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                Example is a typed configuration surface for the repository policy tool.

                ## Installation

                Add the package to your manifest.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // Edge/fail-closed: both constructs present, but only inside a fenced
    // code block — the fence-stripped scan (mirroring README-017/026's
    // fence exclusion) must not see them, so no advisory from either
    // identifier.
    @Test
    func readmeAdvisoriesAreSilentInsideAFencedCodeBlock() throws {
        let root = try repositoryFixture(
            files: [
                "README.md": """
                # Example

                ```markdown
                ![Status](https://img.shields.io/badge/status-active--development-blue.svg)

                ## Platform Support
                ```

                Example is a typed configuration surface for the repository policy tool.
                """
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try RepositoryPolicy.validateSurface(
            repository: "swift-foundations/swift-example",
            repositoryClass: .package,
            root: root,
            policy: .init(schemaVersion: 1, actionGrants: [], exemptions: [])
        )

        #expect(report.advisories.isEmpty)
    }

    // MARK: - Issue-record grammar

    @Test
    func issueRecordParserAcceptsTheCompactTaskProfile() throws {
        let record = try RepositoryPolicy.Issue.Parser.record(
            """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1
            """
        )

        #expect(record.kind == .task)
        #expect(record.owner == "swift-institute/.github")
        #expect(record.status == .active)
        #expect(record.grammarVersion == 1)
    }

    // Positive control: an omitted core field must be reported malformed,
    // not silently accepted as an otherwise clean record.
    @Test
    func issueRecordReconcilerReportsMalformedCore() {
        let report = RepositoryPolicy.Issue.reconcile([
            .init(
                coordinate: "swift-institute/.github#173",
                body: """
                    ### Kind

                    Task

                    ### Owner coordinate

                    swift-institute/.github

                    ### Status

                    Active
                    """,
                native: .init(state: .open)
            )
        ])

        #expect(report.map(\.finding) == [.malformed])
    }

    // Positive control: a core-field profile has one value. The parser must
    // not overwrite a malformed first value with a later conforming one.
    @Test
    func issueRecordReconcilerRejectsAdditionalCoreFieldContent() {
        let report = RepositoryPolicy.Issue.reconcile([
            .init(
                coordinate: "swift-institute/.github#173",
                body: """
                    ### Kind

                    not Task
                    Task

                    ### Owner coordinate

                    swift-institute/.github

                    ### Status

                    Active

                    ### Grammar version

                    1
                    """,
                native: .init(state: .open)
            )
        ])

        #expect(report.map(\.finding) == [.malformed])
    }

    @Test
    func issueRecordReconcilerSeparatesNativeStateAndUnavailableInputs() throws {
        let active = """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1
            """
        let decision = try RepositoryPolicy.Issue.Decision(
            grammarVersion: 1,
            status: "superseded",
            supersededBy: "https://github.com/swift-institute/.github/issues/174"
        )

        let report = RepositoryPolicy.Issue.reconcile([
            .init(coordinate: "z#1", body: nil, native: .init(state: .open)),
            .init(coordinate: "a#1", body: active, native: .init(state: .completed)),
            .init(coordinate: "b#1", body: active, native: .init(state: .open), decision: decision),
            .init(coordinate: "c#1", body: active, native: .init(state: .open, parent: "a#0")),
        ])

        #expect(report.map(\.coordinate) == ["a#1", "b#1", "c#1", "z#1"])
        #expect(report.map(\.finding) == [.stale, .superseded, .conforming, .unavailable])
    }

    @Test
    func issueRecordReconcilerIncludesEveryPage() {
        let report = RepositoryPolicy.Issue.reconcile(pages: [
            .init(
                inputs: [.init(coordinate: "b#2", body: nil, native: .init(state: .open))],
                hasNextPage: true
            ),
            .init(
                inputs: [.init(coordinate: "a#1", body: nil, native: .init(state: .open))],
                hasNextPage: false
            ),
        ])

        #expect(report.map(\.coordinate) == ["a#1", "b#2"])
        #expect(report.map(\.finding) == [.unavailable, .unavailable])
    }

    @Test
    func typedLifecycleRecordsRejectInvalidVersionAndDigest() {
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.CompactionCheckpoint(
                grammarVersion: 2,
                source: "https://github.com/swift-institute/.github/issues/173",
                digest: "0123456789abcdef0123456789abcdef01234567"
            )
        }
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.TerminalReceipt(
                grammarVersion: 1,
                revision: "not-a-revision",
                verification: "workspace package test"
            )
        }
    }

    @Test
    func `Issue snapshot digest matches known vectors across chunk boundaries`() {
        let vectors = [
            ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
            ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
            (String(repeating: "a", count: 64), "0098ba824b5c16427bd7a1122a5a442a25ec644d"),
            (String(repeating: "a", count: 65), "11655326c708d70319be2610e8a57d9a5b959d3b"),
        ]

        for (body, digest) in vectors {
            let snapshot = RepositoryPolicy.Issue.Snapshot(
                coordinate: "swift-institute/.github#183",
                revision: "\"known-vector\"",
                body: body,
                native: .init(state: .open)
            )

            #expect(snapshot.digest == digest)
        }
    }

    @Test
    func activeRecordCompactorRendersOnlyTheCurrentSpecificationAndCheckpoint() throws {
        let body = """
            ### Problem

            Earlier detail remains in the Issue timeline.

            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1

            ### Proposed outcome

            Compact this current body without touching history.
            """
        let snapshot = RepositoryPolicy.Issue.Snapshot(
            coordinate: "https://github.com/swift-institute/.github/issues/174",
            revision: "\"issue-174-v1\"",
            body: body,
            native: .init(state: .open)
        )
        let expected = try RepositoryPolicy.Issue.Guard(
            revision: snapshot.revision,
            digest: snapshot.digest
        )

        let plan = try #require(
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: expected)
        )

        #expect(
            plan.body == """
                ### Kind

                Task

                ### Owner coordinate

                swift-institute/.github

                ### Status

                Active

                ### Grammar version

                1
                """
        )
        #expect(
            try RepositoryPolicy.Issue.Parser.checkpoint(plan.checkpoint).source
                == snapshot.coordinate
        )
        #expect(
            try RepositoryPolicy.Issue.Parser.checkpoint(plan.checkpoint).digest == snapshot.digest
        )
        #expect(!plan.body.contains("Earlier detail"))
        #expect(!plan.checkpoint.contains("Earlier detail"))
    }

    // Positive control: a changed entity tag OR a changed body digest must
    // refuse before any body rewrite or checkpoint can be proposed.
    @Test
    func activeRecordCompactorRefusesStaleRevisionAndDigest() throws {
        let body = """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Active

            ### Grammar version

            1

            ### Problem

            Needs compaction.
            """
        let snapshot = RepositoryPolicy.Issue.Snapshot(
            coordinate: "https://github.com/swift-institute/.github/issues/174",
            revision: "\"current\"",
            body: body,
            native: .init(state: .open)
        )
        let staleRevision = try RepositoryPolicy.Issue.Guard(
            revision: "\"stale\"",
            digest: snapshot.digest
        )
        let staleDigest = try RepositoryPolicy.Issue.Guard(
            revision: snapshot.revision,
            digest: "a9993e364706816aba3e25717850c26c9cd0d89d"
        )

        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: staleRevision)
        }
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: staleDigest)
        }
    }

    @Test
    func activeRecordCompactorRefusesTerminalAndInactiveRecords() throws {
        let body = """
            ### Kind

            Task

            ### Owner coordinate

            swift-institute/.github

            ### Status

            Blocked

            ### Grammar version

            1
            """
        let snapshot = RepositoryPolicy.Issue.Snapshot(
            coordinate: "https://github.com/swift-institute/.github/issues/174",
            revision: "\"current\"",
            body: body,
            native: .init(state: .open)
        )
        let expected = try RepositoryPolicy.Issue.Guard(
            revision: snapshot.revision,
            digest: snapshot.digest
        )

        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: snapshot, guard: expected)
        }
        let terminal = RepositoryPolicy.Issue.Snapshot(
            coordinate: snapshot.coordinate,
            revision: snapshot.revision,
            body: snapshot.body,
            native: .init(state: .completed)
        )
        #expect(throws: RepositoryPolicy.Issue.Error.self) {
            try RepositoryPolicy.Issue.Compactor.plan(snapshot: terminal, guard: expected)
        }
    }

    private func repositoryFixture(files: [String: String]) throws -> URL {
        let root =
            FileManager.default.temporaryDirectory
            .appending(path: "repository-policy-\(UUID().uuidString)")
        for (path, contents) in files {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: file)
        }
        return root
    }

    private func render(_ decision: RepositoryPolicy.Decision) -> String {
        switch decision {
        case .excluded(let reason): reason.rawValue
        case .converged: "converged"
        case .enable: "enable"
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let repository: RepositoryPolicy.Repository
        let manifestKind: String?
        let pvr: String?
        let decision: String

        enum CodingKeys: String, CodingKey {
            case name
            case repository
            case manifestKind = "manifest_kind"
            case pvr
            case decision
        }
    }
}
