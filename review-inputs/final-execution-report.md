# CI/CD Completion Programme — Final Execution Report

Executioner: CI/CD completion coordinator session (Claude, session 3c420ad2), acting for the
principal (coenttb). Reporting date 2026-08-05. Governing authority:
`CI-CD-COMPLETION-PROGRAMME.md` (SHA-256 `62e315c4…`, committed `1705d2aa`), executing the
refactor programme (`184db8ef…`, blob `f6556f1f` at `bb3fa49c`) under Goal
[swift-institute/.github#276](https://github.com/swift-institute/.github/issues/276).
Frozen heads: `frozen-heads.json` (this directory). Predicate adjudication:
`predicate-ledger-final.json` (this directory).

This report is the executioner's declaration required by the E1 commission's §0. It is an
input to review, not proof of its own claims — every coordinate is independently readable.

## 1. Terminal state reached

- **Callers**: 449/449 accessible ordinary package repositories carry the terminal thin
  caller on their default branch (single `ci` job, layer wrapper `@main`, tags `'*'`,
  top-level read-only permissions, `ci-${{ github.ref }}` concurrency, CI-059 secret rule,
  zero migration inputs). Final live structural census: `v1-final-census-result.json`
  (0 faults; both predicates demonstrated firing on synthetic bad rows first).
- **Rulesets**: 449/449 require exactly `ci / matrix / ci-ok`; `bypass_actors: []`
  everywhere; zero `ci / ci-ok` requirers. The R28.1 App bypass window is closed at source
  and live.
- **Wrappers**: three layer wrappers reduced to the semantic layer interface; outer
  aggregates deleted; matrix jobs carry `contents: read / actions: read` (TX7c;
  merges `ea9c5533` / `904ddb4c` / `84ac0109`).
- **Universal reusable**: docs unconditional and exactly-once; `integrated-docs` deleted;
  pins normalized; ci-ok emits the effective runtime receipt with per-subject artifact
  naming. Terminal receipt: run 31010155651 attempt 1, digest `a649e088…`
  (`runtime-receipts/`).
- **Compatibility surfaces**: all deleted with zero-use evidence (ruleset-compat payloads,
  waves, runbook, sync-metadata inputs, nightly hold, CLI `--compatibility`, docs-sweep).
- **TX12**: nested full-tier probe and distinct fork-origin PR both terminal successful
  (runs 31009606407, 31009687887); probe repository deleted by the principal; 404 readback
  positive-controlled.

## 2. G1 — private verification

Seven defects were found and repaired during the live G1 pass, all on
`swift-institute/.github` main (author coenttb, reviewer swift-institute-bot, squash):

| PR | Merge | Defect |
|---|---|---|
| #336 | `31191d19` | sweep App mints scoped to the current repository → R10 false-zero private enumeration |
| #337 | `26b24694` | `::add-mask::` captured by command substitution → every minted token invalid |
| #338 | `e972a541` | sealer/publisher envelope filename mismatch → all publishes failed closed |
| #339 | `70700e31` | mask steps carried subject coordinates in step `env:`; the runner prints env headers before execution → private-coordinate leak in public logs |
| #343 | `fc8037f6` | requested lint lands unmeasured with an absolute path in its reason; redaction guard rightly refuses the seal |
| #347 | `d9f03f07` | verifier pinned Swift 6.3 below Workspace's floor → seal could never compile Workspace on any runner |
| #348 | `3297291d` | init+fetch recipe never creates `origin`; the seal reads the origin URL to establish identity |

Leak remediation: 43 affected public run logs deleted; deleted-log read returns 404
(positive control). Exposure class: private repository/branch coordinates only, public
< 2 hours, no credentials.

**Proven live**: automatic enqueue (sweeps 31015225053, 31016724456, 31019570227);
R10-positive-controlled enumeration across all 17 orgs (dry-run 31014967818, zero
UNMEASURED); fail-closed publish on every defective envelope (100+ runs, zero false
successes); invalid-payload refusal; run/artifact opacity (request-ids only).

**Proven locally at the pinned Workspace revision** (`49fad76`), on the runner's exact
recipe (macOS, image Xcode toolchain, init+fetch+detached-head checkout, clean origin):
`verification seal` → `verified, 3 operation(s)`; `verification check` → consistent.

**Not yet observed**: one green end-to-end run in CI — recorded as
[#349](https://github.com/swift-institute/.github/issues/349) per the principal's
2026-08-05 ruling to record and proceed to review. A confirming canary at head `3297291d`
was queued at freeze time; its green conclusion cited on #349 closes the item without
moving any frozen head. The verifier runs on `macos-26` until the Workspace Linux port
([Workspace#136](https://github.com/swift-institute/Workspace/issues/136)) lands.

## 3. V1 — validation sweep results

- Final caller + ruleset census: 449/449 terminal, 0 faults, positive controls fired
  (`v1-final-census-result.json`).
- App permissions: 24 installations, all `repository_selection: all`; the 17 sweep orgs
  carry an identical 32-scope grant; sole divergent row is a non-Institute account
  (`v1-app-permission-readback.tsv`).
- Durable wave records: `tx6a-records.jsonl` (449 rows, sha256 `d882bc79…`),
  `tx8-records.jsonl` (449 rows, sha256 `15ee62b7…`). The 13 non-terminal wave rows are
  exactly the post-wave repairs; every one is terminal in the final live census, which
  supersedes them.
- Rejection demonstrations: red required leg → `ci / matrix / ci-ok` failure →
  `mergeable_state: blocked` (captured pending AND red) → merge attempt HTTP 405 naming
  the required check verbatim (swift-primitives/swift-array-primitives PR #12; closed
  unmerged, branch deleted).
- Bogus-dispatch refusal: hand-dispatched invalid payload failed closed; run title exposed
  the request-id only.

## 4. Predicate adjudication

See `predicate-ledger-final.json`: 23 MET, P21 DESCOPED (R22.1/R24.3, the sole authorized
descope), P12/P13 BLOCKED on #349, P27/P28 pending E1/R1 by construction. No predicate
other than P12/P13 depends on #349.

## 5. Principal-only actions performed

- `coenttb/swift-single-primitives` deleted by the principal after Class A capture (TX12);
  404 readback positive-controlled.
- Merge-refusal demonstration executed by the principal (HTTP 405 verbatim).
- 2026-08-05 rulings: record #349 and proceed to review; defer Workspace-side fixes to the
  review + decomposition + 100%-Swift programme; re-venue E1 per the commission document.

## 6. Known residue (outside the closure set)

- [#349](https://github.com/swift-institute/.github/issues/349) — G1 end-to-end green
  (closes on citation).
- [#340](https://github.com/swift-institute/.github/issues/340) — pre-existing ownerless
  `botReviewTransactionSourcesCollectionsFromFiles` failure (R28.4).
- [Workspace#136](https://github.com/swift-institute/Workspace/issues/136) — no Linux
  compile; verifier pinned to macOS runners meanwhile.
- `swift-records` nested-red TX-R disposition; ~200 pre-existing-red repositories as a
  post-programme repair stream.
- Principal's post-completion goal: replace #113-exempt non-Swift glue with Swift
  (the E1 commission's Judgment B owns the programme).

## 7. Declaration

Every technical transaction preceding V1 is complete; the V1 sweep at the frozen heads is
complete; receipt-readiness material exists (P19 receipt digest `a649e088…` + this
ledger); the heads submitted for review are frozen in `frozen-heads.json`; the open
evidence items are exactly those in §6. The implementation is ready for the external
review required by R14a/R20 as re-venued by the principal's commission document, with
#349 declared open.
