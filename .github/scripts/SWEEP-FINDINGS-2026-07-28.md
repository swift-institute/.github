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
| `API-IMPL-007` extension file lacking a `+` or ` where ` segment | 1262 | 124 |
| `TEST-009` test file lacking the space before `Tests` | 706 | 179 |
| `API-IMPL-006` compound basename matching no declaration | 693 | 43 |
| `GH-REPO-074` `ci.yml` is not a thin caller | 42 | 11 |
| `CI-059` secrets-forwarding shape | 9 | 7 |
| `PACKAGE-AGGREGATE-EXPORT` non-export content in an exports-only target | 1 | 1 |

**2713 findings across 255 of 471 repositories**, re-measured 2026-07-28 after
two repositories left the corpus (see *Corpus change* below). The first
measurement, over 473 repositories, was 2784 across 257.

The thirteen failing `scan-file-naming` legs are **three causes**, not thirteen
and not one. That distinction was the point of the exercise: a leg count is not
a cause count.

---

## Each rule was checked for adoption before being believed

A check prescribing a shape nothing uses is a defect in the check, not in the
fleet — the same defect as a skill asserting a convention nobody practises. So
adoption was measured over the 473-repository population **before** any
conclusion was drawn about who was wrong. It was not re-measured after the
corpus moved to 471; the two repositories that left carried 71 findings between
them and cannot move a ratio of this size, but the figures below are stated as
of the earlier population rather than silently carried forward:

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
| `swift-standards/swift-stripe-types` | 65 |
| `swift-foundations/swift-authentication` | 65 |
| `swift-primitives/swift-standard-library-extensions` | 60 |
| `swift-iso/swift-iso-9945` | 38 |

Two repositories carry **1262 of the 2713**. The remaining 247 repositories
carry 1011 between them.

`swift-structured-queries-postgres` is one of the three Institute-owned forks
that stay public because they are load-bearing — so 112 of the findings above
sit on code the Institute did not author. See the vendored-fork section.

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

## The vendored-fork question: settled by removal, not by exemption

This section previously asked whether the naming validators should gain a
`vendored-upstream` carve-out, on the grounds that `metadata-schema.json` had
already accepted that argument for READMEs and never generalised it.

**It was resolved on 2026-07-28 by taking the two repositories out of the
corpus instead.** On the principal's instruction,
`swift-institute/fork-swift-parsing` and
`swift-institute/pointfree-url-form-coding` are now **private and archived** —
verified by reading the API, not by trusting the instruction. Both were
vestigial: packages had been moved out of a personal org into
`swift-foundations` and reworked to fit Institute code, and these two were left
behind.

Since enumeration filters to public and non-archived, they drop out
automatically. No exemption axis was added and no fork was bent to Institute
conventions.

**Three forks stay public because they are load-bearing**, and will appear in
the corpus: `swift-tagged-primitives`, `swift-url-routing`,
`swift-structured-queries-postgres`. `cclsp` was deliberately left alone — it
looks like a development tool rather than a package dependency, so its zero
dependent count does not carry the same meaning.

**The general question is therefore deferred, not answered.** Nothing has been
decided about whether an Institute-owned fork that *is* load-bearing should be
held to Institute naming conventions. The three above are in scope today and
`swift-structured-queries-postgres` already carries findings. Expect this to
return; the removal resolved two instances, not the principle.

### Corpus change, measured rather than subtracted

The population moved from 473 to 471. The finding total was **re-measured** on
refreshed clones rather than reduced on paper — two repositories leaving a
corpus is exactly the sort of change that should be observed:

| | Before (473) | Now (471) | Delta |
|---|---:|---:|---:|
| Findings | 2784 | 2713 | −71 |
| Repositories with findings | 257 | 255 | −2 |

The two repositories that left the finding list are exactly the two archived,
and **no repository newly entered it**. The 71 findings are precisely those two
repositories' own. The re-measurement happens to agree with the subtraction —
which is a stronger statement than the subtraction would have been, because it
also establishes that nothing else in the corpus moved.

One caution on the enumeration used for that re-measure: the first attempt
returned a delta of ~470 repositories, which is absurd on its face and was the
only reason it got a second look. `for org in $ORGS` does not word-split in
**zsh**, so the whole org list interpolated into one URL and the enumeration
returned nothing; every repository then appeared to have left. Run enumeration
under `bash` explicitly. An implausible number is a measurement to re-check
before it is a finding to report.

## Provenance

Raw finding data was produced by the method above and is regenerable; it is not
checked in, because a stale copy of a measurement is worse than none. The
sweep's own defects — counters narrower than their validators, unread sentinel
rows, an unread tracking issue, and six validators producing no jobs at all —
are recorded in `VALIDATOR-DISCIPLINE.md` and
`SWEEP-COVERAGE-GAPS-2026-07-28.md`.
