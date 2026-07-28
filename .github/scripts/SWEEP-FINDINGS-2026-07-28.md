# What the weekly validator sweep is reporting

Measured 2026-07-28. Companion to `VALIDATOR-DISCIPLINE.md`, which covers how
the sweep's own instruments were wrong; this file covers what they found once
they were right.

This is a work queue, not a postmortem. It is a committed document rather than
a tracking issue because issues are ruled out as a durable location for this
phase, and a finding that lives only in a transcript is a finding that is gone.

---

## Method, so the numbers can be audited

Enumerated the 17 active orgs **unfiltered**: 664 repositories. Scope applied as
a separate, named step — public and non-archived — leaving **473**. Both numbers
stated on purpose; see `CONVERGENCE-DISCIPLINE.md` §1.

The three org-sweep validators were then run from this repository against a
local clone of every one of those 473, rather than by scraping CI logs. The
findings live in per-cell step summaries, which are not reachable from the run
list or the API, so log-scraping would have measured what was easy to read
rather than what was there.

**The reproduction was checked against CI before it was trusted.** The set of
orgs with `API-IMPL-*` findings matched the 12 failing `scan-file-naming` legs
exactly, and the set with `GH-REPO-074` matched the 3 failing
`scan-thin-callers` legs exactly. Three individual findings were sampled and
verified by reading the files; all three were correct.

One caution for whoever re-runs this. `validate-package-structure.py` resolves
`exports.swift` paths **relative to the current working directory**, and CI runs
it from inside the cloned repo. A first local pass run from elsewhere reported
zero findings — a clean result produced by a harness pointed at the wrong place.
The local/CI disagreement is what surfaced it.

---

## The findings

| Rule | Findings | Repos |
|---|---:|---:|
| `API-IMPL-007` extension file lacking a `+` or ` where ` segment | 1265 | 125 |
| `TEST-009` test file lacking the space before `Tests` | 753 | 181 |
| `API-IMPL-006` compound basename matching no declaration | 713 | 44 |
| `GH-REPO-074` `ci.yml` is not a thin caller | 43 | 12 |
| `CI-059` secrets-forwarding shape | 9 | 7 |
| `PACKAGE-AGGREGATE-EXPORT` non-export content in an exports-only target | 1 | 1 |

**2784 findings across 257 of the 473 repositories.**

The thirteen failing `scan-file-naming` legs are **three causes**, not thirteen
and not one. That distinction was the point of the exercise: a leg count is not
a cause count.

---

## Each rule was checked for adoption before being believed

A check prescribing a shape nothing uses is a defect in the check, not in the
fleet — the same defect as a skill asserting a convention nobody practises. So
adoption was measured over the same 473 repositories **before** any conclusion
was drawn about who was wrong:

| Convention | Adopted | Population |
|---|---:|---|
| dotted basename (`API-IMPL-006`) | 6781 | 12079 `Sources/**/*.swift` (56%) |
| `+` extension segment (`API-IMPL-007`) | 1948 | 12079 (16%) |
| ` Tests.swift` (`TEST-009`) | 2693 | 3446 test files (78%) |

All three are genuinely practised — 1948 files carry a `+` segment, which is not
the signature of a convention nobody adopted. **No validator is retired here.
The fleet changes.**

Recording the negative result explicitly, because it is the one that would have
justified deleting a check: nothing in this set resembles the 0-of-94 case that
retired an earlier gate.

---

## Shape of the work

Heavily concentrated, with a long mechanical tail:

| Repo | Findings |
|---|---:|
| `swift-foundations/swift-css-html-render` | 939 |
| `swift-foundations/swift-html-render` | 323 |
| `swift-foundations/swift-structured-queries-postgres` | 112 |
| `swift-standards/swift-postgresql-standard` | 100 |
| `swift-institute/fork-swift-parsing` | 70 |
| `swift-standards/swift-stripe-types` | 65 |
| `swift-foundations/swift-authentication` | 65 |
| `swift-primitives/swift-standard-library-extensions` | 60 |

Two repositories carry 1262 of the 2784. The remaining 237 repositories carry
785 between them.

### No cheap fix turns a leg green

Checked rather than assumed. Every org's `scan-package-structure` leg is
currently red for the unscanned-target cause in
`SWEEP-COVERAGE-GAPS-2026-07-28.md`, so **no organisation can be made green by
clearing naming findings** until that is resolved. Sequence the coverage gap
first; otherwise the naming work buys no visible change and reads as wasted.

### One repository is not a cheap fix, despite appearing to be

`swift-institute/swift-web-foundation` is the sole `PACKAGE-AGGREGATE-EXPORT`
finding, and the validator reports only the **first** offending line, which makes
it read like a one-character change. It is not: all 20 non-comment lines of
`Sources/WebFoundation/exports.swift` are rejected — 15 `@_exported import`
lines lacking `public`, plus a 5-line `extension ParserPrinter` block that does
not belong in an exports-only target. Adding `public` changes re-export
semantics under Swift 6 and the extension needs a home, so this is a deliberate
change to that package's public surface and belongs to whoever owns it.

Generalise the lesson rather than the instance: **a validator that reports the
first violation per file understates every multi-violation file**, and a triage
built on finding counts will mis-size exactly those.

---

## Settle this before renaming anything

Two repositories in scope are verbatim vendored upstream code:

- `swift-institute/fork-swift-parsing` — a fork of `pointfreeco/swift-parsing`,
  carrying **70 findings**. Its README is upstream's, badges and all.
- `swift-institute/pointfree-url-form-coding` — self-described as a fork of
  Point-Free's `swift-web/UrlFormEncoding`.

Both declare `readme.family: E`, i.e. ordinary Institute sub-packages.

`metadata-schema.json` has **already reasoned this through** for READMEs. The
`readme.exempt: vendored-upstream` value exists precisely because editing
vendored files to satisfy Institute conventions "buys a cosmetic gain and pays
permanent divergence and harder merges forever". But that exemption covers
README routing only, and **nothing equivalent exists for the naming
validators**. Its adoption across the fleet is **1 of 473** repositories
(`swift-institute/cclsp`).

So an argument the Institute has already accepted has not been generalised, and
the naming validators currently hold third-party code to conventions written for
Institute-authored code. Renaming 70 files in a fork is the thing that reasoning
says not to do.

This is a policy question, not a lint fix, and it changes what the target state
*is* — so it belongs before the tail is worked, not after.

---

## Provenance

Raw finding data was produced by the method above and is regenerable; it is not
checked in, because a stale copy of a measurement is worse than none. The
sweep's own defects — counters narrower than their validators, unread sentinel
rows, an unread tracking issue, and six validators producing no jobs at all —
are recorded in `VALIDATOR-DISCIPLINE.md` and
`SWEEP-COVERAGE-GAPS-2026-07-28.md`.
