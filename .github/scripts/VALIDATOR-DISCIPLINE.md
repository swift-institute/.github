# Validator discipline

Written 2026-07-28, after four checks in this repository were found to be
producing green results while measuring nothing. It is a postmortem and a
method, kept beside the validators so that whoever edits one finds it.

The one-line version:

> **A gate without a positive control is not evidence, regardless of how it is
> pinned.**

What the 2026-07-28 sweep audit found, using this method, is recorded in two
companion files rather than repeated here:

- `SWEEP-FINDINGS-2026-07-28.md` — what the validators are reporting once their
  counters were corrected, with the adoption measurement that establishes the
  fleet is wrong rather than the checks.
- `SWEEP-COVERAGE-GAPS-2026-07-28.md` — the two populations the sweep was
  reporting on without having measured them.

---

## 1. The extractor postmortem

A gate enforced a 250-character ceiling on each skill's frontmatter
`description`. It ran on every push and pull request, logged what it scanned,
and reported success. It had never measured a description.

The extractor:

```awk
/^description:/ { flag = 1; next }
flag && /^[a-z_]+:/ { exit }
flag { print }
```

`next` consumes the `description:` line itself, so the count begins on the line
*after* it and continues until a line that looks like a top-level key. What this
measures is **the distance to the next frontmatter key** — a quantity that has
no fixed relationship to the length of a description.

It read as correct for months because the corpus happened to make it correct.
Frontmatter carried trailing keys:

```yaml
---
name: audit
description: |
  Check code against conventions and record findings.
  Apply when auditing convention compliance.

layer: process        # <- the scan stopped here
requires:
---
```

`layer:` terminated the scan after two lines. Every skill "passed."

Then a commit removed those trailing keys as part of adopting
progressive-disclosure hubs. Nothing stopped the scan any more, so it ran past
the closing `---` and consumed each **entire skill body**. All 42 skills flipped
from compliant to violating in a single commit.

**No description changed.** Both runs logged `Scanned 42 skill(s)`, ceiling 250,
allowlist 1 entry. The observable signals were identical.

### The theory that was wrong, and why it was seductive

The first explanation offered was that the caller pinned the reusable workflow
at `@main` — a floating ref — so the green and red runs executed different
workflow code, and green→red was the gate *starting to work*.

Every fact in that account checked out. The caller really was pinned to a
floating ref. The reusable really was modified between the last green run and
the first red one. Floating refs really are a defect worth fixing. It is a good
theory, and it is wrong.

Reading the diffs settles it: the only change to the reusable in that window
altered **three lines, all action pins** (`actions/checkout@v4`→`v7`, a
harden-runner digest bump). Nothing behavioural. The other candidate commit
changed the script's *default* roots, which the caller overrode explicitly.
Running the retired script against both corpus revisions directly, it exits
non-zero on **both** — so "the gate started working" cannot be right either.

The flip came from a **corpus** commit, not from the checker.

The lesson generalises past this incident: **a causal story assembled from true
facts is still a hypothesis.** Diff-reading is cheap; the theory survived one
retelling because nobody spent five minutes on it.

### What it implies about ref-pinning

Pinning is worth doing — see §5 — but it would **not** have caught this. The
defect was in the checker's own parsing. A perfectly pinned checker measuring the
wrong thing is exactly as inert as an unpinned one. Pinning makes a green run
*attributable to a version*; only a control makes it *meaningful*. If you
propagate the pinning lesson alone, the next inert gate will be pinned and still
inert.

---

## 2. The four inert gates

Individually each reads as bad luck. The set is the argument.

| Gate | Failure mode | How it looked |
|---|---|---|
| Description ceiling | Measured the distance to the next frontmatter key | Ran, scanned 42 skills, logged the count, reported success |
| Rule-claim guard | All three checks unreachable; corpus inputs gone | Gating in the weekly sweep, printing a coverage line |
| Skill-hygiene self-test | Guarded on visibility only; consumer path never exercised | Green on every run it had ever had |
| Skill-size gate | Wired to no workflow at all | A checked-in gate implying a live rule |

Four distinct mechanisms. One shared property: **every one of them looked like
coverage.** Not one was noticed by reading its output.

### The most insidious shape

The rule-claim guard printed:

```
checked 12 skill files: 0 VERIFICATION artifacts, 0 prose claims,
2 bound claims, 1 bound numerics.
```

`2` and `1` are `len()` of two **hardcoded tables**. Only the zeros are derived
from the corpus. A reader scans that line, sees non-zero numbers, and reads
coverage.

This is worse than a silent zero, because it **manufactures the appearance of
measurement**. A zero invites the question "did it look at anything?" A
plausible non-zero closes it.

If a validator prints a coverage figure, that figure must be derived from what it
actually inspected. A constant rendered as a measurement is a lie the code tells
in good faith.

### On honesty not being sufficiency

To its credit, the rule-claim guard printed:

> green here does NOT mean those citations were checked. Deleting one of them
> would still pass.

It was **honest about being unable to conclude** — better than most inert gates.
It still ran as a gating job, so what it contributed in practice was a permanent
green tick. A caveat in the log is not a control. If a check cannot fail, its
disclaimer does not make it a gate; it makes it a well-documented no-op.

---

## 3. Control patterns

Method, not results. Each of these caught something real.

### Inject a violation and watch it fire

The only way to establish that a check can fail. For each rule the checker
claims to enforce, construct an input that must trigger it, and **watch it
trigger**. Reasoning about whether it would is not the same act.

This is what settled the rule-claim guard. Rather than arguing about whether its
inputs still existed, three deliberate violations were injected into a copy of
the live corpus, one per check. All three exited 0. That is a result; an
argument would not have been.

Fixtures under `tests/fixtures/<rule>/fail/` are the durable form of this — the
runner fails the suite if a `fail/` fixture stops producing a finding.

### Mutation-test the check itself

A `fail/` fixture proves the check fires *today*. To prove the fixture is
load-bearing, break the check on purpose and confirm its fixture goes red.

Disabling one branch of the link-resolution check turned
`skill-links/fail/dangling-companion` red. Had it stayed green, the fixture was
decorative.

### Prove parameters in both directions

A parameter that threads through and is then **ignored** produces a run
indistinguishable from one that honoured it.

For the `validator-ref` pin: pointing it at a commit predating the validator must
**fail** (script absent), and pointing it at `main` must **pass**. Ignored, both
would have passed. Only the pair is evidence.

**A negative control that cannot fail is the same defect as a gate that cannot
fail.** The first attempt at that control was invalid: the "pre-validator" commit
was derived from a misattributed SHA after `main` moved, so the script was
present and the control could not have failed. It was caught before a conclusion
was drawn from it — but it nearly shipped inside the fix for exactly that class
of defect.

### Guard mirror conditions

When two jobs are meant to be mutually exclusive, guard them on **mirrored
predicates** (`inputs.repo == ''` / `inputs.repo != ''`) rather than on unrelated
conditions. Otherwise one path runs everywhere and the other runs nowhere, and
the green you have is over the path you exercised.

The skill-hygiene self-test was guarded on repository visibility alone. In-repo
it ran and passed; on a consumer's call it checked out the consumer's tree, where
the fixtures do not exist, and died. **Green over a path nobody has run is the
same failure as green over a check that cannot fire.**

### Diff the rules a validator EMITS against the rules its workflow COUNTS

Two lists, in two files, that must agree and have nothing holding them
together. The validator grows a rule; the workflow's counting regex does not;
the finding is computed, printed into a TSV, and then dropped on the floor.

Measured 2026-07-28 across the 473 public non-archived repositories in the 17
active orgs:

| Workflow | Counted | Validator also emits | Findings discarded |
|---|---|---|---|
| `validate-file-naming.yml` | `API-IMPL-*` | `TEST-009` | 753, in 181 repos |
| `validate-thin-callers.yml` | `GH-REPO-074` | `CI-030`, `CI-059` | 9 |

The same regex filters the summary table, so the discarded findings were not
merely uncounted — they were invisible. Worse, **three legs reported success
while carrying real violations**, because in those orgs the dropped rule was the
org's *only* finding. The sweep said 16 legs were failing; 19 had findings.

This is harder to notice than an inert gate, because the check is working. It
scans, it finds, it is right. Only the last step throws the answer away, and the
green it produces is over a genuinely-scanned population.

The check is mechanical and takes a minute: grep the validator for every rule
string it can `emit()`, and confirm the workflow's regex admits each one. Do it
whenever a validator gains a rule — which is exactly when nobody thinks to.

### A report nobody is notified about is not a report

The weekly sweep did file a tracking issue. It had been filing one since
2026-05-19, updating it in place every week, and it had **zero comments and zero
notifications** in ten weeks.

`gh issue edit --body-file` rewrites a body and notifies nobody. So the
mechanism that looked like reporting was, in delivery terms, a no-op — the same
category as the gates above, one layer out: it produced an artifact rather than
a signal.

Two more defects sat behind it, each invisible while the first held:

- The label the workflow passed **did not exist in the repository**. The upsert
  action applies a label on CREATE and silently falls back to a label-less
  create, so the issue never had one, and the edit path cannot repair that.
- The close-when-clean step searched by that label while the upsert searched by
  title-prefix. **The two never referred to the same issue**, so auto-close could
  not fire even on a fully clean fleet — a mirror-condition defect (see above)
  in which only the path that runs weekly was ever exercised.

When you add a reporting path, ask what would actually reach a person, and then
check that it did. An artifact that exists is not the same as a signal that
arrives; and the count belongs where it can be seen without clicking — a title,
not only a body.

### Check what the checker is actually looking at

`gh repo clone` takes the **default branch**. Every validator on the shared base
therefore inspected `main` on pull requests and never saw the change under
review — so a pull request introducing a violation passed, and the push run went
red only after the content had landed.

This surfaced because a pull request adding a required file went red while the
identical pinned validator was clean against that branch locally. Both tempting
responses were wrong: "fix" the pull request to satisfy the red, or merge past
the red trusting the local green. Running **both trees** settled it — `main` gave
six findings, the branch gave zero.

When local and CI disagree, the disagreement is the finding. Resolve it before
acting on either.

### Fail closed on "did not run"

"Scanned nothing" must never be reportable as "found nothing." Distinguish
*clean* from *did not execute*, and fail on the latter:

- clone failed
- validator exited non-zero
- pull-request head could not be checked out
- no input files found at all

The empty-corpus guard exists because the description gate's whole failure was a
scan that reported on a population it never measured.

---

## 4. What was declined, and why

Both of these will be proposed again. They were refused deliberately.

### A credential-scanning regex

Not built. Secret scanning and push protection are already enabled on the public
repositories. A hand-rolled pattern would be strictly weaker, would not block the
push, and would false-positive on a corpus that legitimately *discusses* secret
transport.

Adding a check that duplicates a stronger existing control, worse, is not
defence in depth. It is a second thing to maintain and a second place to
disable.

### A private-repository-internals check

Not mechanically enforceable, and not approximated.

A public README may legitimately name a private repository's **existence** so a
reader can tell why some material is absent. Disclosing its **contents** would be
a leak. No pattern separates those, and any attempt produces a rule about what
constitutes a leak — a judgement that does not belong in a linter.

**But the disposition was initially wrong, and that error is the more useful
one.** The residue was routed to "human review." On a fleet where one account
authors and merges — and where GitHub will not accept that account's approval of
its own pull request — there is no moment at which such a review can block. That
is not a slower control. **It is an absent control wearing the label of one**,
which is the same defect as an unverified enforcement claim in a README.

The resolution keeps the refusal and fixes the disposition. The check adjudicates
nothing; it asks only whether a cross-repository reference is **new**. Listed →
silent. Unlisted → the build stops, and the person adding the mention decides, in
the change that adds it, while the intent is in front of them.

Three design decisions carry that:

1. **The list lives in the scanned repository**, not beside the validator, so the
   entry and the mention land in the same pull request. Beside the validator it
   would have been the retired gate again: remote, unowned, edited by whoever was
   unblocking a build.
2. **Sanctioning an owner arms its namespace.** Listing one reference under an
   owner makes every *other* reference under that owner visible.
3. **Narrow the owner, not the shape.** Matching every `A/B`-shaped token yields
   25 candidates in the corpus of which 24 are prose — `A/B`, `CI/CD`, `ISO/IEC`,
   `Tests/Package.swift`. **A list that is 96% noise gets appended to reflexively
   rather than read**, which reproduces the failure of the allowlist on the gate
   just retired. Narrowing the owner keeps the list short enough that a human
   reads it.

A control from that work is worth keeping: an early pattern swallowed the full
stop that ends a sentence, so a reference written as `…projected from Owner/Name.`
was reported as `Owner/Name.` — a token that can never match a list entry. **A
check that fires on correctly sanctioned text is worse than one that misses**,
because it teaches everyone that the list does not work and trains them to route
around it.

### The residue, stated at its true size

Do not let a record describe a smaller gap than exists.

- Repositories in `swift-*` and `rule-*` namespaces: **watched** (54 of the
  fleet's 59 org namespaces).
- The remaining namespaces — unrelated ventures and a personal account:
  **unwatched, permanently, by construction**. A public file enumerating them
  would be the disclosure it guards against. *You cannot watch for a name you are
  unwilling to write down.*
- Whether a watched reference discloses anything: **still not judged**, by
  design.

An earlier version of this check watched only the 17 orgs in the bot's sweep
manifest — a scope authored for nightly settings convergence, not for namespace
watching. Inheriting a boundary drawn for another purpose left 42 namespaces
unwatched, including a parallel institute. Check what a list was *for* before
reusing it as a control surface.

---

## 5. Pinning: what it buys and what it does not

Callers should pin reusable workflows **and** the validator script to the same
commit. A floating ref means a green tick cannot be attributed to any particular
version of the checker; pinning only the workflow leaves the script floating,
which is most of the exposure.

**This closes script float. It does not make a validator correct.**

The gate retired here was pinned to nothing and inert. A perfectly pinned checker
whose logic measures the wrong thing is equally inert — and would have been
reliably, reproducibly wrong. Pinning makes a green run *reproducible*; a
positive control makes it *mean something*. Do not let a pinned validator invite
confidence it has not earned.

---

## 6. Before wiring a validator

- Every rule it claims to enforce has a `fail/` fixture, and that fixture has
  been **watched to fire**.
- Something has been made to fail **through the whole path it will run in**, not
  only against a local fixture. The skill-hygiene checker passed its fixtures
  perfectly and still shipped two holes, because the fixtures never went through
  the shared base.
- Any coverage figure it prints is derived from what it inspected.
- "Did not run" is distinguishable from "found nothing", and fails.
- Its fixtures are executed by a workflow. An untriggered suite is the same
  category of artifact as an unproven gate: it looks like coverage and provides
  none. This repository's suite ran nowhere for months.
- It is green against the target before it is made blocking. A gate nobody can
  pass teaches contributors to read red as normal, which is worse than having no
  gate.
- Every rule the validator can emit is admitted by the workflow's counting
  regex. Two lists in two files that must agree, with nothing holding them
  together, is the cheapest silent-drop in the repository.
- Whatever reports its findings actually reaches a person, and that has been
  observed rather than assumed. A weekly artifact that notifies nobody is the
  same failure one layer out from the gate.

## 7. On a detector that is correctly, permanently red

Not every red is a defect to clear. The weekly sweep is a *detector* over a
fleet the Institute is still converging; when the checks are right and the fleet
is genuinely non-conforming at scale, red is the accurate reading and the fleet
is what changes.

What is not acceptable is red that carries no information. The failure here was
never the colour — it was that three consecutive weeks of red were
indistinguishable from each other, from a validator crash, and from a repo that
failed to clone. Before treating a standing red as noise, establish which it is:

- Can the run tell you *how many* legs failed, and *which*, without opening
  cells one at a time?
- Can it distinguish "found violations" from "never ran"?
- Has the count moved? A number that has not changed in ten weeks and a number
  nobody has ever read look identical.

Fix the legibility first. A red you can read is a work queue; a red you cannot
is just a broken light, and people correctly learn to ignore broken lights.
