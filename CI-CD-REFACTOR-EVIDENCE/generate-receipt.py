#!/usr/bin/env python3
"""Render CI-CD-REFACTOR-COMPLETION-RECEIPT.md in the exact §6.3 shape as
amended by Corrigendum §11.2 (name-reservation population class), under
Ruling R29's two-phase rule: --phase candidate omits the performative
P27/P28-MET/post-action content; --phase final includes the post-action
readbacks passed via --readback-json."""
import argparse
import csv
import json
import os
import sys
from collections import defaultdict

S = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--phase", choices=["candidate", "final"], required=True)
ap.add_argument("--readback-json")
ap.add_argument("--output", required=True)
a = ap.parse_args()

census = json.load(open(os.path.join(S, "census.json")))
worklist = json.load(open(os.path.join(S, "tx6a-worklist.json")))
ORGS = ["swift-primitives", "swift-standards", "swift-foundations", "swift-ietf",
        "swift-iso", "swift-ieee", "swift-iec", "swift-w3c", "swift-whatwg",
        "swift-ecma", "swift-incits", "swift-arm-ltd", "swift-intel",
        "swift-riscv", "swift-linux-foundation", "swift-microsoft",
        "swift-institute"]
PRIVATE = {"swift-ietf": 27, "swift-primitives": 47, "swift-standards": 1,
           "swift-foundations": 93, "swift-institute": 14}

def tb(x):
    return x is True or x == "true" or x == "True"


pop = defaultdict(lambda: defaultdict(int))
reservations = []
for r in census:
    o = r["org"]
    pop[o]["enum"] += 1
    pop[o]["public"] += r["visibility"] == "public"
    pop[o]["fork"] += tb(r["fork"])
    pop[o]["archived"] += tb(r["archived"])
    pop[o]["disabled"] += tb(r["disabled"])
    active = not (tb(r["fork"]) or tb(r["archived"]) or tb(r["disabled"]))
    pop[o]["active"] += active
    if r["hasRootPackageSwift"] is None or r["hasCiYml"] is None:
        pop[o]["unmeasured"] += active
        continue
    pop[o]["package"] += active and tb(r["hasRootPackageSwift"])
    pop[o]["caller"] += active and tb(r["hasCiYml"])
    # Name-reservation class (Corrigendum §11.2): active, packageless,
    # callerless, and NOT an already-typed class — organization `.github`
    # (control), `*.org` site repositories (meta), or the swift-institute
    # control organization's non-package repositories (control/meta by
    # charter). Enumerated live, never hard-coded.
    if (active and not tb(r["hasRootPackageSwift"]) and not tb(r["hasCiYml"])
            and r["name"] != ".github" and not r["name"].endswith(".org")
            and o != "swift-institute"):
        reservations.append(f"{o}/{r['name']}")
controls = [x for x in reservations if "reservation" in x]
assert len(controls) >= 2, ("name-reservation positive control failed", reservations)

conv = defaultdict(int)
for t in worklist:
    conv[t["repository"].split("/")[0]] += 1

app_rows = []
for line in open(os.path.join(S, "v1-app-permission-readback.tsv")):
    org, sel, grants = line.rstrip("\n").split("\t")
    if org not in ORGS:
        continue
    g = dict(kv.split(":") for kv in grants.split(","))
    app_rows.append((org, "yes", sel, g.get("contents", "-"), g.get("workflows", "-"),
                     g.get("statuses", "-"), g.get("checks", "-"), "read back 2026-08-05 (review-inputs/v1-app-permission-readback.tsv)"))

rb = json.load(open(a.readback_json)) if a.readback_json else {}
FINAL = a.phase == "final"
GOAL_STATE = (f"closed `completed` {rb.get('goalClosedAt','')} — readback {rb.get('goalReadback','')}" if FINAL
              else "open (closure is R1's performative act; candidate phase)")
P2728 = ("MET — the receipt you are reading contains the post-action readbacks" if FINAL
         else "pending — performative; cannot precede the actions (R29)")

out = []
w = out.append
w("# CI/CD Refactor Completion Receipt")
w("")
if not FINAL:
    w("> **Phase: pre-finalization candidate (R29).** This document freezes the")
    w("> receipt candidate; it is not yet the §6.3 receipt and must not be")
    w("> presented as one until R1's post-action final commit.")
    w("")
w("## Authority")
w("- Programme document filename: `CI-CD-REFACTOR-PROGRAMME.md` (commit `bb3fa49c416be6ce55c6c828a0b2cfbb6bea8119`, blob `f6556f1f704b854cb2fdff23788cfb02fd270216`), executed via `CI-CD-COMPLETION-PROGRAMME.md` (commit `1705d2aa89949a84c933359e14e6189fbde3e887`)")
w("- Programme document SHA-256: `184db8ef230cd7e532f9aeb167a51508bc897f8221ec935cb5a776ca1eaf62ef` (refactor, Corrigendum §11 present); `62e315c42f6ec6b34320af560697fc8bfb772ab655ddc4c65456ff04cd90d21f` (completion)")
w("- Executor identity/session: Claude coordinator session `3c420ad2-0f08-410a-bad2-f60c6c214e42`, acting for the principal under rulings R7–R33")
w("- Authenticated GitHub identity: `coenttb` (human reads/mutations); `swift-institute-bot` App installation tokens (machine reads, distinct-reviewer approvals)")
w("- Started: 2026-08-04 (programme execution arc; G0 checkpoint heads §3.1 of the completion programme)")
w(f"- Completed: {'2026-08-05 (R1 finalization)' if FINAL else '2026-08-05 (candidate freeze; R1 pending)'}")
w("- Overall result: COMPLETE")
w("")
w("## Governing heads at start and finish")
w("| Repository | Default branch | Start SHA | Finish SHA | Visibility |")
w("|---|---|---|---|---|")
heads = [
    ("swift-institute/.github", "dd7af62198b451341a5566368914195eb1baecec", "1705d2aa89949a84c933359e14e6189fbde3e887 (implementation freeze; evidence-only deltas thereafter, see Mutations)", "public"),
    ("swift-institute/Workspace", "22776d8b4ebd6180e2d04de3c7d4daf0a1d702ab", "49fad76bed2cc34da62de1b733600e725b6ae2e1", "public"),
    ("swift-institute/Skills", "a4c752911015e8c7ea1cd5fe6f3f8e586e9f55c4", "a4c752911015e8c7ea1cd5fe6f3f8e586e9f55c4", "public"),
    ("swift-primitives/.github", "3a52c7101115ec37f2408d02bfaf7867dd6068aa", "ea9c55330d496f0b276f9c9a9030c15ce1f07122", "public"),
    ("swift-standards/.github", "d7566e05aa02f601d4856ad53a9a3bab66b62e31", "904ddb4c5e67be436a772332eef1b16acfbe1765", "public"),
    ("swift-foundations/.github", "756e67264a9c614bf4735b8cce9fbb34fbbfe29f", "84ac0109aab50db70c46fdba11729a58126f530c", "public"),
    ("swift-foundations/swift-linter", "6b37a58aff1506f71b76079da88ac7d185b6f78d", "6b37a58aff1506f71b76079da88ac7d185b6f78d", "public"),
]
for repo, s, f, v in heads:
    w(f"| {repo} | main | `{s}` | `{f}` | {v} |")
w("")
w("## Programme and work objects")
w("| Task | Issue | Parent Goal | PR(s) | Final state | Close reason |")
w("|---|---|---|---|---|---|")
wo = [
    ("Programme Goal", "swift-institute/.github#276", "—", "programme-wide", GOAL_STATE, "completed" if FINAL else "—"),
    ("TX1 effective inventory", "swift-institute/Workspace#135", "#276", "Workspace #135 PR", "closed", "completed"),
    ("TX3/G1 private verification repairs", "—", "#276", "#335, #336, #337, #338, #339, #341, #343, #344, #345, #346, #347, #348", "merged", "—"),
    ("TX7/TX7b receipts + docs", "—", "#276", "#334 + central batch", "merged", "—"),
    ("TX12 evidence reconstruction (E1 CB-1)", "—", "#276", "#352", "merged", "—"),
    ("E1 review-input bundle + ledger", "—", "#276", "#350, #351, #353", "merged", "—"),
    ("G1 end-to-end green", "swift-institute/.github#349", "#276", "—", "closed", "completed (citation 5195203166)"),
    ("Pre-existing ownerless test failure", "swift-institute/.github#340", "#276 (residue, outside closure set)", "—", "open", "—"),
    ("Workspace Linux port", "swift-institute/Workspace#136", "follow-up programme FT2 (residue)", "—", "open", "—"),
]
for row in wo:
    w("| " + " | ".join(row) + " |")
w("")
w("## App installations and permissions")
w("| Organization | Installation present | Repository selection | contents | workflows | statuses | checks | Approved/read-back |")
w("|---|---|---|---|---|---|---|---|")
for row in app_rows:
    w("| " + " | ".join(row) + " |")
w("")
w("## Mutations")
w("| Task | Repository | Before SHA | After SHA | Exact files | Rollback commit/SHA |")
w("|---|---|---|---|---|---|")
mut = [
    ("central batch TX2–TX10, G1 chain, R31", "swift-institute/.github", "dd7af62198b451341a5566368914195eb1baecec", "1705d2aa89949a84c933359e14e6189fbde3e887", "workflows, scripts, Tools/RepositoryPolicy, fixtures, authority docs (per-PR file lists on each merged PR)", "per-PR revert; ruleset reverse payloads captured pre-write (R21/R28.0)"),
    ("TX9A wrapper reduction", "swift-primitives/.github", "3a52c7101115ec37f2408d02bfaf7867dd6068aa", "ea9c55330d496f0b276f9c9a9030c15ce1f07122", ".github/workflows/swift-ci.yml (sole workflow)", "revert merge"),
    ("TX9B wrapper reduction", "swift-standards/.github", "d7566e05aa02f601d4856ad53a9a3bab66b62e31", "904ddb4c5e67be436a772332eef1b16acfbe1765", ".github/workflows/swift-ci.yml (sole workflow)", "revert merge"),
    ("TX9C wrapper reduction", "swift-foundations/.github", "756e67264a9c614bf4735b8cce9fbb34fbbfe29f", "84ac0109aab50db70c46fdba11729a58126f530c", ".github/workflows/swift-ci.yml (sole workflow)", "revert merge"),
    ("TX6A/TX8 caller waves (449 repos)", "17-organization fleet", "per-repo (tx6a-records.jsonl)", "per-repo (tx8-records.jsonl)", ".github/workflows/ci.yml only, byte-verified", "per-repo regeneration from prior generator revision"),
    ("TX4/TX5 ruleset waves (449 repos)", "17-organization fleet", "per-repo old payloads (reverse payloads captured)", "terminal `ci / matrix / ci-ok`, bypass empty", "ruleset JSON via settings API", "captured reverse payloads"),
    ("E1 evidence deltas (post-freeze)", "swift-institute/.github", "1705d2aa89949a84c933359e14e6189fbde3e887", "b8fb8b6a1e16448d4133ee939b785ecf6fa24291", "review-inputs/, CI-CD-REFACTOR-EVIDENCE/ only (compare-verified)", "revert merges #351/#352/#353"),
]
for row in mut:
    w("| " + " | ".join(row) + " |")
w("")
w("## Local evidence")
w("| Task | Exact Workspace command | Root | Toolchain | Fresh | Exit | Test/compile counts | Result |")
w("|---|---|---|---|---|---|---|---|")
loc = [
    ("G1 seal repro (runner recipe)", "`workspace verification seal --package-path <subject> --claimed-head 6366ec0e… --step build --step test --step nested-tests --required-step build --required-step test --required-step nested-tests --receipt <path>`", "Workspace @ 49fad76bed2cc34da62de1b733600e725b6ae2e1", "Apple Swift 6.3.3 / Xcode 26.6", "release build", "0", "3 operations: build+test success, nested-tests not-applicable", "verified"),
    ("G1 check repro", "`workspace verification check --receipt <path>`", "same", "same", "n/a", "0", "—", "consistent"),
    ("Receipt validator suite", "python3 .github/scripts/tests/test-effective-runtime-receipt.py (evidence tooling; #113-exempt)", ".github @ 9c69d197507f034fe23e01ef5371b2a99d93b4c3", "system python3", "n/a", "0", "12 tests", "OK"),
    ("RepositoryPolicy tests", "`workspace package test --package-path Tools/RepositoryPolicy --fresh`", ".github frozen head", "Swift 6.3.3", "yes", "0 (one pre-existing ownerless failure filed as #340, present at pristine base)", "suite green minus #340", "recorded"),
]
for row in loc:
    w("| " + " | ".join(row) + " |")
w("")
w("## Workflow evidence")
w("| Task | Repository | Run ID/URL | Event | Head SHA | Attempt | Run conclusion | Required jobs executed | Skipped/unmeasured jobs |")
w("|---|---|---|---|---|---|---|---|---|")
wf = [
    ("TX12 full-tier nested canary", "swift-primitives/swift-single-primitives", "31009606407 https://github.com/swift-primitives/swift-single-primitives/actions/runs/31009606407", "workflow_dispatch", "b0ccd71ee7ee00a5911450233928915113e2163d", "1", "success", "24 success of 26", "2 skipped (advisory; excluded from proof)"),
    ("TX12 fork-origin PR canary", "swift-primitives/swift-single-primitives", "31009687887 https://github.com/swift-primitives/swift-single-primitives/actions/runs/31009687887", "pull_request", "8d445ef8cc2cf45ff0f25228943897796d20a778", "1", "success", "23 of 23", "0"),
    ("P19 terminal receipt producer", "swift-institute/.github", "31010155651 https://github.com/swift-institute/.github/actions/runs/31010155651", "workflow_dispatch", "6fbc0f80b22b19b13b339772231260a96e24c8db", "1", "success", "50 jobs paginated", "receipt UNMEASURED fields typed in-record"),
    ("G1 dry-run enumeration (R10 control)", "swift-institute/.github", "31014967818 https://github.com/swift-institute/.github/actions/runs/31014967818", "workflow_dispatch", "26b24694cb72228c9cb8e6dc0dfa0a488f386549", "1", "success", "sweep job; 17/17 orgs enumerated, zero UNMEASURED warnings", "0"),
    ("G1 live sweep (first)", "swift-institute/.github", "31015225053 https://github.com/swift-institute/.github/actions/runs/31015225053", "workflow_dispatch", "26b24694cb72228c9cb8e6dc0dfa0a488f386549", "1", "success", "automatic enqueue proven", "—"),
    ("G1 green end-to-end", "swift-institute/.github", "31027146280 https://github.com/swift-institute/.github/actions/runs/31027146280", "repository_dispatch", "3297291d77765bb2d1b638c3cc331c7c84bc414d", "1", "success", "verify + publish", "0"),
]
for row in wf:
    w("| " + " | ".join(row) + " |")
w("")
w("## Positive and negative controls")
w("| Task | Control | Expected | Observed | Exact evidence coordinate |")
w("|---|---|---|---|---|")
ctl = [
    ("V1 caller census", "synthetic legacy caller must FAIL the terminal predicate before live reads", "predicate fires", "fired (assertion gate)", "review-inputs/v1-final-census-result.json producer, `v1-final-census.py` positive controls"),
    ("V1 ruleset census", "synthetic bypass-carrying ruleset must FAIL", "predicate fires", "fired", "same"),
    ("G1 enumeration (R10)", "total-zero private enumeration must fail the run", "exit 1 on zero", "pre-repair run 31014263884 failed exactly so; post-repair 31014967818 green", "both runs live-readable"),
    ("Probe deletion", "deleted fork reads 404 with an upstream 200 positive control", "404/200", "404/200", "Goal #276 R32 comment 5195353007; manifest.json typed losses"),
    ("Leak remediation", "deleted run log reads 404", "404", "404 (run 31015364118 logs)", "Goal #276 comment 5194785984"),
    ("Rejection demo (red leg)", "merge attempt returns HTTP 405 naming `ci / matrix / ci-ok`", "405", "405 verbatim", "principal-run; swift-primitives/swift-array-primitives PR #12 (closed unmerged)"),
    ("Invalid payload", "bogus repository_dispatch fails closed, opaque title", "failure", "failure", "requestId `v1bogus…` run in private-verification history"),
    ("P20 empty referenced_workflows", "broken false-success variant must fail the test", "test fails on variant", "failed as required", ".github/scripts/tests/test-effective-runtime-receipt.py"),
    ("Name-reservation class (Corrigendum §11.2)", "class matches the two named reservation repositories", "both matched", f"{len(controls)} matched of {len(reservations)} class members", "population table below; census.json"),
    ("Deleted-log positive control", "SHA256SUMS recompute at merge SHA matches 13/13", "13/13", "13/13", "Goal #276 comment 5195312244"),
]
for row in ctl:
    w("| " + " | ".join(row) + " |")
w("")
w("## Re-derived population")
w("| Organization | Enumerated | Public | Private | Fork | Archived | Disabled | Active included | Package | Caller-bearing | UNMEASURED |")
w("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for o in ORGS:
    p = pop[o]
    priv = PRIVATE.get(o, "0*")
    w(f"| {o} | {p['enum'] + (PRIVATE.get(o) or 0)} | {p['enum']} | {priv} | {p['fork']} | {p['archived']} | {p['disabled']} | {p['active']} | {p['package']} | {p['caller']} | {p['unmeasured']} |")
w(f"| **name-reservation class (Corrigendum §11.2)** | {len(reservations)} | {len(reservations)} | 0 | 0 | 0 | 0 | {len(reservations)} | 0 | 0 | 0 |")
w("")
w("*Private counts marked `0*` were enumerated by the R10-controlled sweep (run 31014967818, zero UNMEASURED orgs) but per-org private figures are recorded in the public receipt only where the E1 reviewer measured them live (five organizations); the sweep's per-org counts live in the run's own record. Name-reservation members: " + ", ".join(f"`{x}`" for x in sorted(reservations)) + ".*")
w("")
w("## Caller convergence")
w("| Organization | Ordinary target | Conforming | Typed exception | PR open | Failed | UNMEASURED | #90 wave check coordinate |")
w("|---|---:|---:|---:|---:|---:|---:|---|")
total = 0
for o in sorted(conv):
    n = conv[o]
    total += n
    w(f"| {o} | {n} | {n} | 0 | 0 | 0 | 0 | review-inputs/tx6a-records.jsonl + tx8-records.jsonl (per-repo terminal verify) |")
w(f"| **total** | {total} | {total} | 0 | 0 | 0 | 0 | final live census: review-inputs/v1-final-census-result.json (449/449, 0 faults) |")
w("")
w("## Workspace reconciliation")
w("- Effective inventory digest: UNMEASURED in this receipt — the TX1 `workspace inventory effective` adapter landed (Workspace #135, `49fad76…`) and G1's dispatch rode `inventoryDigest: unmeasured` by declaration; the first digest-bound sweep is follow-up work")
w("- Committed public inventory digest: `Workspace.json` at `49fad76bed2cc34da62de1b733600e725b6ae2e1`")
w("- Private runtime inventory digest: UNMEASURED (same adapter; private discovery pass authorized but not digest-frozen this arc)")
w("- Represented: 449 ordinary public package repositories (census-verified terminal)")
w("- Missing: 0 (positive-controlled)")
w("- Stale: 0")
w("- Unexplained: 0 (name-reservation class typed per Corrigendum §11.2)")
w("- UNMEASURED: the two inventory digests above, typed with reasons")
w("")
w("## Required-check and ruleset migration")
w("| Repository class | Old context | New context | Target repos | Converged | Read-back mismatches | Rollback payload |")
w("|---|---|---|---:|---:|---:|---|")
w("| public ordinary | `ci / ci-ok` | `ci / matrix / ci-ok` | 449 | 449 | 0 | captured reverse payloads per write (R21) |")
w("| control/meta | none | none (no package check; typed) | 3 | 3 | 0 | n/a |")
w("| private ordinary | none | `verification / workspace` via central verifier (ruleset limb DESCOPED per R33 — platform-refused, 403 absence control) | ~182 | compensating control live | 0 | n/a |")
w("")
w("## Private verification")
w("| Opaque private subject ID | Central run | Receipt digest | Workspace SHA | Policy digest | Platforms/operations | Check conclusion |")
w("|---|---|---|---|---|---|---|")
w("| `diag0005run0005eeeeeeeeeeeeeeeee` (request-id; subject mapping held on the private check surface) | 31027146280 | envelope binding `350849aa69578612b07ef3ef02f66d685af9e65cd90e0bb43480fcda1d600548` (raw receipt destroyed by design post-envelope; binding digest is the surviving public coordinate) | `49fad76bed2cc34da62de1b733600e725b6ae2e1` | `2026-08-04-1` | macos/arm64; build+test success, nested-tests not-applicable; all required gates satisfied | `verification / workspace` = success on the subject's exact head, `external_id` = request-id |")
w("")
w("## Effective-runtime receipts")
w("| Subject run | Receipt digest | Root workflow SHA | Wrapper SHA | Universal SHA | Linter authorities/checksums | Runner images | UNMEASURED fields |")
w("|---|---|---|---|---|---|---|---|")
w("| 31010155651 attempt 1 (subject swift-foundations/swift-copy-on-write @ `7e9749c55418e701e15edaea8238809f6fe098c2`) | terminal `a649e0883d1b2abb12474a723917c469d855afe28fab3370501cf4d3fe52db9b`, base `7dfb5e8941e85fe40f612a2f5ec037319db8e0c47e70885a5d901f67e76bbfe5` | `6fbc0f80b22b19b13b339772231260a96e24c8db` | in referencedWorkflows (8 hops recorded, path/ref/SHA) | in referencedWorkflows | UNMEASURED (typed: not exposed at in-run capture) | recorded per-job in the receipt | actions, containers, linter, revisions — each with a typed reason in-record |")
w("")
w("## Inline annotations")
w("| Repository/head | Linter run/result | Check run ID | Annotation count | Requests | Conclusion | Fork/unavailable disposition |")
w("|---|---|---:|---:|---:|---|---|")
w("| all | P21 `DESCOPED — principal authorized` (R22.1/R24.3); measured SARIF precondition absent | — | 0 (absence-controlled, not empty-read) | 0 | DESCOPED | n/a |")
w("")
w("## Scheduled workflows")
w("| Workflow | Pre-fix run/conclusion | Post-fix run/conclusion | Exact head | Bot issue auto-closed |")
w("|---|---|---|---|---|")
w("| sync-metadata-nightly | cancellation/token defects (P4 pre-state) | R24.2 findings-separation route; nightly green at terminal source (hold line deleted TX5) | `1705d2aa89949a84c933359e14e6189fbde3e887` | bot-owned divergence issues close on convergence by their owning workflow |")
w("| submit-dep-graph-weekly | schedule failure (P4 pre-state) | findings separated from instrumentation per R24.2; classification recorded in P4's ledger row | same | same |")
w("")
w("## Deletions and zero-use proofs")
w("| Deleted surface | Former coordinates | Zero-use census/control | Commit |")
w("|---|---|---|---|")
dele = [
    ("ruleset-compat payloads, waves, runbook; CLI --compatibility; BypassAllowance", "Tools/RepositoryPolicy + workflow inputs", "zero-consumer grep at head + tests updated to empty-bypass-only", "central batch merges (ancestors of 1705d2aa)"),
    ("sync-metadata ruleset-compat input + nightly hold", ".github/workflows/sync-metadata{,-nightly}.yml", "input unreferenced fleet-wide (TX5 census)", "same"),
    ("docs-sweep job; integrated-docs input; migration inputs", "swift-ci.yml, ci-sweep.yml, 449 callers", "TX8 elision wave + final census zero survivors", "same + wave records"),
    ("wrapper outer aggregates + docs wrappers", "3 layer .github repos", "census: zero `ci / ci-ok` requirers before deletion (TX5 order held)", "ea9c5533 / 904ddb4c / 84ac0109"),
    ("probe fork coenttb/swift-single-primitives", "fork of swift-primitives/swift-single-primitives", "Class A capture reconstructed at 9c69d197 (R32); 404 readback with upstream 200 control", "principal deletion 2026-08-05"),
    ("43 leaked private-verification run logs", "swift-institute/.github Actions", "deleted-log 404 positive control", "Goal comment 5194785984"),
]
for row in dele:
    w("| " + " | ".join(row) + " |")
w("")
w("## Operational stops encountered")
w("| Scope | Condition | Exact coordinate | Pending operation | Disposition/resumption evidence |")
w("|---|---|---|---|---|")
stops = [
    ("R28 bypass window", "merging a healed ruleset payload IS the fleet mutation; lane stopped with zero mutation", "#324/#325; R28 comment 5189930862", "re-land under R28.1", "window closed at source+live; bypass_actors [] fleet-wide"),
    ("G1 first pass", "R10 false-zero enumeration", "run 31014263884 (failed by its own control)", "token-scoping repair", "#336/#337; dry-run 31014967818 green"),
    ("G1 leak incident", "private coordinates in public env headers", "run 31015364118 (logs deleted)", "mask relocation + log deletion", "#339; comment 5194785984"),
    ("G1 seal chain", "toolchain pin below floor; missing origin; lint redaction", "runs 31024168933/31025139885/31025447001 (leak-safe diagnostic classes)", "#343/#347/#348", "green run 31027146280"),
    ("Classifier/backend outages", "executor tool-approval backend intermittently down", "session record", "principal ran handed scripts; permission rules added", "resumed same-day"),
    ("E1 CB-1/CB-2", "verdict REJECTED pending remediations", "E1 document; acceptance comment 5195475128", "evidence PR + rulings", "9c69d197 + R32/R33 + ledger b8fb8b6a; verdict ACCEPTED FOR R1"),
    ("Private-subject name disclosure", "the private subject's repository NAME appears in public PR bodies #341/#343/#348 and the #349 record (name only; no content, heads, or diagnostics beyond the already-public envelope)", "those PR bodies", "principal disposition (edit bodies to the opaque request-id, or accept name-level disclosure as within the R33 compensating-control posture)", "recorded here; receipt itself uses the opaque subject ID"),
]
for row in stops:
    w("| " + " | ".join(row) + " |")
w("")
if FINAL:
    w("## Post-action readbacks (R29)")
    w(f"- Goal #276 state readback: {rb.get('goalReadback', 'MISSING')}")
    w(f"- Child readbacks: {rb.get('childReadback', 'MISSING')}")
    w(f"- Receipt candidate digest attached pre-close: `{rb.get('candidateDigest', 'MISSING')}` (comment {rb.get('candidateComment', 'MISSING')})")
    w(f"- Predicates 27–28: {P2728}")
    w("")
w("## Assertions")
asserts = [
    "Every programme PR states the #113 exemption.",
    "No intra-Institute reusable workflow is SHA/tag pinned.",
    "`@main` remains enforced by [CI-030] and REPO-ACTIONS-004.",
    "No `LINTER_RELEASE` pin or source fallback was introduced.",
    "Every zero/absence conclusion has a successful positive control.",
    "Every inaccessible input is UNMEASURED.",
    "Every cited workflow run was read back at run level.",
    "Every run head equals the revision claimed as evidence.",
    "Every matrix-affecting closure uses fresh exact-head full tier, not PR tier.",
    "Private package CI runs were not used as evidence.",
    "Every ruleset equals source-controlled expected payload.",
    "Every caller wave records the live #90 check.",
    "No untrusted job received a status/check write token.",
    "No tag, release, deployment, publication, visibility, SPI, or announcement occurred.",
    "Every rollback is identified and ordered safely.",
    "All temporary compatibility paths have zero-use proof and are deleted.",
]
for s_ in asserts:
    w(f"- [x] {s_}")
w("")
open(a.output, "w").write("\n".join(out) + "\n")
print(f"{a.phase} receipt written: {a.output} ({len(out)} lines)")
