# What the weekly sweep still cannot see

Measured 2026-07-28. Two open coverage gaps in `lint-validators-weekly.yml`,
both surfaced by making previously-silent failures fail closed.

Neither is a defect in a validator. Both are cases where the sweep reported on a
population it had not measured — the shape `CONVERGENCE-DISCIPLINE.md` opens
with: *a success signal is not a measurement.*

Committed here rather than tracked as issues, which are ruled out as a durable
location this phase.

---

## 1. `validate-package-structure` never scanned 81% of its targets

### What was wrong

The check step has always written two sentinel rows into its findings file —
`clone-failed` and `package-describe-failed` — and the aggregation never read
either. Neither matches the `^PACKAGE-` predicate the violation count uses, so a
repository whose manifest would not resolve counted **exactly like a repository
with no findings**. The validator never ran on it; the leg went green.

Closed in `962ce46`: both sentinels are counted and fail the leg.

### What that revealed

First run with the gates live ([run 30376757233]), across the smaller orgs whose
legs completed:

| Org | Targets | Never scanned |
|---|---:|---:|
| swift-standards | 29 | 28 |
| swift-w3c | 7 | 6 |
| swift-iec | 3 | 2 |
| swift-whatwg | 3 | 2 |
| swift-arm-ltd, swift-ecma, swift-incits, swift-intel, swift-microsoft | 2 each | 1 each |
| swift-linux-foundation | 1 | 1 |

**44 of 54 targets — 81% — were never scanned**, and every one of those legs had
been reporting success. Violations found in the 10 that *were* scanned: 0. The
green was not wrong about those 10; it was silent about the other 44.

### The cause is NOT established

Two hypotheses were tested and **both refuted**. Recording the refutations
because the next person will have the same two ideas:

1. *Private dependencies needing credentials `swift package describe` does not
   have.* Every `swift-standards` package manifest was checked against the list
   of private repositories in the 17 orgs: **zero** have a private dependency.
2. *The packages themselves do not resolve.* All 29 `swift-standards`
   repositories were cloned and the identical
   `swift package --skip-update describe --type json` run locally: **all
   succeed**.

So the failure is environmental to the CI runner, not a property of the
repositories.

A plausible remaining candidate — **offered as inference, not measurement** — is
contention on the shared SwiftPM cache, since these legs run many concurrent
resolves on a self-hosted macOS runner. It has **not** been tested and must not
be treated as the answer.

`3e04abb` prints each unscanned target's reason to the job log rather than only
to the step summary, so the next run should diagnose itself. Start there.

### Disposition

**These legs stay red until the cause is fixed.** Reverting the gate would
restore the false green, which is the defect rather than the symptom: the sweep
would go back to reporting clean over 44 repositories it never opened.

---

## 2. Six of the ten validators produced no jobs at all

### What was wrong

`resolve-targets` enumerated **0** `(org, repo)` pairs and exited **0**. Every
Wave-B scan job — `docc-structure`, `package-shape`, `platform-architecture`,
`readme`, `diagnostic-format`, `layer-deps` — received an empty matrix, so it
produced **no jobs whatsoever** and reported `skipped`. The report job counted
`skipped` as clean.

The mechanism was one line. The `--jq` filter built an **array**, and
`gh --paginate` runs the filter once per **page**, so an org with more than 100
repositories produced several concatenated JSON arrays. `jq 'length'` then
returned several numbers and the arithmetic expansion died with
`syntax error in expression`.

**That error appears in the log of every affected run, twice** — once for
`swift-primitives` (202 repos) and once for `swift-foundations` (138) — and was
never read, because the step exited 0 either way.

### When, measured rather than inferred

| Run date | Pairs enumerated |
|---|---:|
| 2026-06-09 | 131 |
| 2026-06-16 | 131 |
| 2026-06-23 | 131 |
| 2026-06-30 | **0** |
| 2026-07-03 | **0** |
| 2026-07-07 | **0** |
| 2026-07-14 | **0** |
| 2026-07-21 | **0** |
| 2026-07-28 | **0** |

Six consecutive runs at zero since 2026-06-30 — and the earlier 131 was **also
wrong**. Note that 473 − 202 − 138 = 133, within two repositories of 131: the two
orgs over 100 repos contributed **nothing** even in the apparently-working
regime. The bug was always there; only its blast radius changed.

**What took it from 131 to 0 around 2026-06-30 is not established.** Recorded as
an open question rather than guessed at. Fixing the enumeration did not require
answering it, and a plausible story would have been indistinguishable from a
verified one.

Throughout, the sweep filed a tracking issue describing coverage of
"~788 matrix cells across 10 validators" while running four.

### What was fixed, and what was not

`d89a27c` makes three changes, because any one alone would have left the failure
silent in a different way:

- The filter streams **one name per line**, and enumeration failure is fatal
  rather than falling back to an empty array. Verified against the live API:
  **473** pairs across the 17 orgs at the time, matching an independent
  enumeration of the same population exactly. The population is now 471; two
  repositories were archived later the same day.
- **Zero targets fails closed.** Zero here is a broken instrument, not a small
  number, and its entire signature is producing no jobs for anyone to notice.
- **`skipped` is no longer clean**, and the validators that did not run are named
  in an error annotation. A validator that did not run is not a validator that
  found nothing — the rule this repository already applies to clone failures,
  one level up.

### What is left: a capacity design

At **471** targets the pre-existing 256-cell GitHub Actions matrix guard now
fires, so `resolve-targets` fails and the six validators **still do not run** —
but loudly, and named, instead of silently reporting clean. That is the intended
intermediate state, not a regression.

The workflow's own header already anticipated this: *"Wave B needs to split scan
jobs by layer or org-group."* It now has to happen.

### Ruled 2026-07-28: take the org-sweep loop, not the per-repo matrix

Two shapes were available and the trade is not close.

| Shape | Jobs per weekly run | Notes |
|---|---:|---|
| Per-repo matrix, chunked `-a`/`-b` | 6 × 471 ≈ **2,800** | clears the matrix limit, leaves the cost untouched |
| **Org-sweep loop** (chosen) | 6 × 17 = **102** | one job scans many repositories |

**Decision: the org-sweep loop.** It matches the shape already proven by the
four validators that do work — `validate-file-naming.yml` and its siblings —
rather than inventing a third pattern for the same job.

This changes `validate-base.yml`'s single-target contract, and that is the
point rather than a concession: **that contract is what makes these six
unrunnable at fleet scale**, so changing it is the fix. The change is
reversible, so it was not escalated further.

**Not yet implemented.** Recorded here so the decision is durable rather than
living in a session transcript. Whoever implements it should carry over the
three properties the four working validators already have and that the sweep
audit had to add to them: count every rule the validator emits, fail closed on
targets that were never scanned, and echo counts to stdout rather than only to
the step summary.

The four org-sweep scanners depend on `config`, not `resolve-targets`, so they
are unaffected either way — the job split that makes that true is worth keeping.

[run 30376757233]: https://github.com/swift-institute/.github/actions/runs/30376757233
