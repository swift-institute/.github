# Ruleset convergence operator runbook

**Goal:** `swift-institute/.github#276` (Task 3-02). **Programme document SHA-256:**
`184db8ef230cd7e532f9aeb167a51508bc897f8221ec935cb5a776ca1eaf62ef`.

This is what the principal runs to execute each convergence wave, what to read
back after each, and what to run to reverse one. It assumes no prior context
beyond a working `gh` CLI authenticated as an identity with admin access to the
target repositories/organizations, and `jq`.

**Agents do not run any command in this document against a live repository.**
Modifying repository security settings (branch-protection rulesets) is a
prohibited action class for agents — this stays true regardless of any
authorization, from the principal or anyone (swift-institute/.github#276 Ruling
R22.2). Every command below is executed by the principal, through the existing
`sync-metadata.yml` `rulesets` job. This runbook, the wave index
(`ruleset-convergence-waves.json`), the four ruleset payload JSON files, and
the reverse-payload capture mechanism built into the `rulesets` job are the
agent-produced artefacts; running them is not.

## Before any wave

1. Confirm Task 3-01's source PR is merged to `swift-institute/.github` `main`
   and note its exact merge SHA.
2. Confirm the App installation permission table (`statuses=write,
   checks=write, contents=write, workflows=write`) is still `APPROVED` for
   every organization the wave touches (Task 00-03 / Ruling R1a).
3. Read the four committed payload files so you know exactly what you are
   about to apply — they are the ground truth, this document only narrates
   them:
   - `Tools/RepositoryPolicy/Policy/protected-main-ruleset.json` — target
     public contract (`ci / matrix / ci-ok` only).
   - `Tools/RepositoryPolicy/Policy/protected-main-public-compatibility-ruleset.json`
     — migration-window public contract (`ci / ci-ok` AND `ci / matrix /
     ci-ok`).
   - `Tools/RepositoryPolicy/Policy/protected-main-private-ruleset.json` —
     private contract (`verification / workspace` only).
   - `Tools/RepositoryPolicy/Policy/protected-main-control-ruleset.json` —
     control-plane contract (unchanged; no required-check rule at all).
4. **Always dry-run first.** Every command below has `dry-run: true`. Read
   its output in full before re-running with `dry-run: false`.

## The one command shape every wave uses

Every wave is a `gh workflow run sync-metadata.yml` dispatch against
`swift-institute/.github`, varying only `repo`/`org`, `visibility`, and
`ruleset-compat`. General shape (single repository):

```sh
gh workflow run sync-metadata.yml \
  --repo swift-institute/.github \
  --ref main \
  -f repo="<owner>/<name>" \
  -f apply-rulesets=true \
  -f ruleset-compat=<true|false> \
  -f dry-run=<true|false>
```

Organization-wide (bounded — pass `org`, not `repo`; `visibility` filters which
repositories in that org are targeted):

```sh
gh workflow run sync-metadata.yml \
  --repo swift-institute/.github \
  --ref main \
  -f org="<organization>" \
  -f visibility=<public|private> \
  -f apply-rulesets=true \
  -f ruleset-compat=<true|false> \
  -f dry-run=<true|false>
```

After dispatch, find the run and watch it to completion:

```sh
run_id=$(gh run list --repo swift-institute/.github --workflow sync-metadata.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --repo swift-institute/.github --exit-status
```

## Step-by-step (matches `ruleset-convergence-waves.json`'s `order`)

### 1. `canary-public-overlap`

Pick 1-3 small, low-traffic public package repositories as the canary. Dry-run,
read the output, then apply:

```sh
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f repo="<canary-owner>/<canary-repo>" -f apply-rulesets=true \
  -f ruleset-compat=true -f dry-run=true
# read the run's log, then:
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f repo="<canary-owner>/<canary-repo>" -f apply-rulesets=true \
  -f ruleset-compat=true -f dry-run=false
```

**Read back:**

```sh
gh api "repos/<canary-owner>/<canary-repo>/rulesets" --jq \
  '.[] | select(.name == "Institute protected main")'
```

Confirm `required_status_checks` lists exactly `ci / ci-ok` and
`ci / matrix / ci-ok`, nothing else. Open a real PR against the canary
repository and confirm it cannot merge until both contexts are green, and that
it CAN merge once both are green plus one approval.

### 2. `canary-private-switch` — **gated, do not run yet**

Precondition: `verification / workspace` is live and forgery/replay-resistant
(Task 2-01/2-02, `swift-institute/.github#253`). **`#253` is open as of
2026-08-04.** Re-check its state before running this step:

```sh
gh issue view 253 --repo swift-institute/.github --json state,title
```

If still open, stop here — this is a task-local stop (§6.2), not a blanket
programme stop. Steps 1 and 3 (public) do not depend on it.

Once `#253` is closed with its stated evidence, the command shape is identical
to step 1 with `-f ruleset-compat=false` (no compatibility variant exists for
private) and a private canary repository.

### 3. `public-fleet-switch` (two phases — see the wave index's `note`)

**Phase (a), per bounded organization wave** — same as step 1 but org-scoped:

```sh
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f org="<organization>" -f visibility=public -f apply-rulesets=true \
  -f ruleset-compat=true -f dry-run=true
# read output; if clean:
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f org="<organization>" -f visibility=public -f apply-rulesets=true \
  -f ruleset-compat=true -f dry-run=false
```

Repeat per organization. Bounded means: one organization (or a small,
deliberately chosen subset of its repositories via repeated `repo=` calls) per
dispatch, not all 17 organizations in one call. Read back and confirm
mergeability (a real PR merges cleanly) before moving to the next
organization.

**Phase (b), once phase (a) is validated for that wave** — drop to the target
payload for the same scope:

```sh
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f org="<organization>" -f visibility=public -f apply-rulesets=true \
  -f ruleset-compat=false -f dry-run=true
# read output; if clean:
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f org="<organization>" -f visibility=public -f apply-rulesets=true \
  -f ruleset-compat=false -f dry-run=false
```

This is safe before the wrapper's `ci-ok` job is deleted (step 7): dropping a
required-check requirement never blocks a merge, it only stops the ruleset
from gating on that context. The wrapper's `ci-ok` job keeps running, now
harmlessly unrequired, until step 7.

**Read back after phase (b):**

```sh
gh api "repos/<owner>/<repo>/rulesets" --jq \
  '.[] | select(.name == "Institute protected main") | .rules[] | select(.type == "required_status_checks")'
```

Confirm exactly one context, `ci / matrix / ci-ok`.

### 4. `private-fleet-switch` — gated on `#253`, same gate as step 2

```sh
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f org="<organization>" -f visibility=private -f apply-rulesets=true \
  -f ruleset-compat=false -f dry-run=true
```

Before applying for real against any repository, confirm that repository
itself has a fresh `verification / workspace` check at a recent head:

```sh
gh api "repos/<owner>/<repo>/commits/main/check-runs" --jq \
  '.check_runs[] | select(.name == "verification / workspace")'
```

An empty result means that repository is not ready for this wave yet — leave
it on whatever it currently has (likely no Institute ruleset at all, or the
pre-3-01 misclassified payload) rather than converging it to a context that
can never report.

### 5. `control-meta-verification` — read-only

No mutation. Enumerate every repository classified `control-plane` (declared
overrides in `Tools/RepositoryPolicy/Policy/ruleset-class-overrides.json` plus
every repository the mechanical Package.swift-absence probe would classify
control) and confirm none carries a `required_status_checks` rule at all:

```sh
for target in <control-plane-repo-list>; do
  gh api "repos/$target/rulesets" --jq \
    --arg t "$target" \
    '.[] | select(.name == "Institute protected main (control)") | if (.rules | map(.type) | index("required_status_checks")) then error("\($t): control-plane repo has a required_status_checks rule") else empty end'
done
```

A non-empty error output here means a control-plane repository was
misclassified as `package` somewhere upstream — stop and investigate before
step 6.

### 6. `zero-use-proof`

```sh
for org in $(yq -r '.[]' <organizations-list>); do
  gh api --paginate "orgs/$org/repos?per_page=100" --jq '.[].full_name' | while read -r target; do
    gh api "repos/$target/rulesets" --jq \
      --arg t "$target" \
      '.[] | select(.rules[]?.parameters.required_status_checks[]?.context == "ci / ci-ok") | "\($t): still requires ci / ci-ok"'
  done
done
```

**Require zero lines of output.** Any output names a repository that phase (b)
of step 3 (or step 4's equivalent — private repositories never require
`ci / ci-ok` in the first place) missed. Do not proceed to step 7 until this
enumeration is clean. If quota-limited, page through organizations separately
and record `UNMEASURED` for any organization not reached rather than treating
an incomplete sweep as a clean zero (§3.1 zero-result protocol).

### 7. `wrapper-deletion` — not this task; reused work objects

Three separate PRs, filed and merged as their own protected-main transactions
against `swift-primitives/.github#12`, `swift-standards/.github#8`,
`swift-foundations/.github#7`. Removes each wrapper's `ci-ok` job (the block
whose comment reads "TEMPORARY, compatibility-only... deletion tracked at
`<owner>/.github#N`" in each wrapper's `swift-ci.yml`). This runbook does not
repeat those PRs' content — see the linked issues.

### 8. `post-deletion-canaries`

```sh
gh workflow run ci.yml --repo <public-canary-owner>/<public-canary-repo> --ref main
gh workflow run sync-metadata.yml --repo swift-institute/.github --ref main \
  -f repo="<private-canary-owner>/<private-canary-repo>" -f apply-rulesets=true -f dry-run=true
```

Read back both runs' `conclusion` at run level (`gh run view <id> --json
conclusion,headSha,event`), and re-read the ruleset on both canaries to
confirm the required context is still exactly what step 3/4 phase (b) set —
wrapper deletion must not have changed what the ruleset requires, only what
producer emits it.

### 9. `delete-temporary-compatibility-policy`

A source PR against `swift-institute/.github` that removes:

- `sync-metadata.yml`'s `ruleset-compat` input and the
  `desired_package_public_compat` computation branch.
- `RepositoryPolicy.Ruleset.protectedMainPublicCompatibilityPayload`.
- `Tools/RepositoryPolicy/Policy/protected-main-public-compatibility-ruleset.json`.

Only after step 6 has passed clean **and** steps 7-8 have landed — a wave that
still needs reversal between step 3 and this step may need to re-apply the
compatibility payload, which requires this code and file to still exist.

## Reversing a wave

Every apply run (dry-run false) that changes a ruleset writes an exact reverse
payload per repository to `${{ runner.temp }}/reverse-payloads/<owner>_<repo>.json`
inside the `rulesets` job, and the job uploads them as a workflow artifact
named `reverse-ruleset-payloads-<run-id>-<run-attempt>` (`if-no-files-found:
warn` — a fully-converged run with nothing to change legitimately produces
none).

1. Find the run that applied the wave you want to reverse and download its
   artifact:

   ```sh
   gh run download <run-id> --repo swift-institute/.github \
     --name "reverse-ruleset-payloads-<run-id>-<run-attempt>" --dir ./reverse-payloads
   ```

2. Each file is one of two shapes:

   - `{"target": "...", "action": "restore", "rulesetId": <id>, "name": "...", "payload": {...}}`
     — the exact ruleset GitHub returned for that repository immediately
     before this run's mutation. Reverse with:

     ```sh
     jq '.payload' "./reverse-payloads/<owner>_<repo>.json" \
       | gh api -X PUT "repos/<owner>/<repo>/rulesets/<rulesetId>" --input -
     ```

   - `{"target": "...", "action": "delete", "rulesetId": <id>, "name": "..."}`
     — this run performed a first CREATE; nothing existed before it to
     restore to. Reverse with:

     ```sh
     gh api -X DELETE "repos/<owner>/<repo>/rulesets/<rulesetId>"
     ```

3. Read back after every reversal:

   ```sh
   gh api "repos/<owner>/<repo>/rulesets/<rulesetId or a fresh listing after delete>"
   ```

**Before wrapper deletion (steps 1-6):** reversing is exactly the two
procedures above — the old producer (the wrapper's `ci-ok` job) is still live,
so restoring a ruleset that requires it is immediately mergeable again.

**After wrapper deletion (step 7 onward):** reversing a ruleset ALONE is not
sufficient if the reverse payload requires `ci / ci-ok` and that job no longer
exists — every repository whose ruleset you restore to a pre-step-7 shape
would deadlock. Restore the wrapper's `ci-ok` job first (revert the step-7 PR
in the affected wrapper repository, merge, confirm the job runs again), THEN
apply the reverse ruleset payload. This order is load-bearing — reversing
these two changes in the wrong order reproduces the exact `#194` deadlock this
whole programme phase exists to remove.

Private trusted status (`verification / workspace`) is never removed merely
because a public wave rolls back — the two visibility tracks are independent;
reversing step 3/8 does not touch anything step 2/4 did.

## What "done" looks like

- `ruleset-convergence-waves.json` step 6 enumeration returns zero lines.
- All three wrapper `swift-ci.yml` files have no `ci-ok` job.
- Every public package repository's live ruleset requires exactly
  `ci / matrix / ci-ok`.
- Every private package repository's live ruleset requires exactly
  `verification / workspace`.
- No control-plane repository's live ruleset carries a
  `required_status_checks` rule.
- `protected-main-public-compatibility-ruleset.json` and its Swift/workflow
  surface are removed (step 9).
- Fresh exact-head public full-tier and private verification runs both
  conclude `success`, read back from the run objects themselves.
