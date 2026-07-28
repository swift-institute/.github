# Convergence discipline

Written 2026-07-28, after a fleet-wide repository-settings convergence found
that the pipeline meant to apply those settings had been dead for a day, that a
successful API call had changed nothing, and that a workflow had been reporting
`converged` for repositories that were not. It is a postmortem and a method,
kept beside the validators because the same failure shape produces both a bad
gate and a bad sweep.

Companion to `VALIDATOR-DISCIPLINE.md`, which covers the same disease in checks
rather than in convergence.

The one-line version:

> **A success signal is not a measurement. Measure the population.**

Everything below is a specific way that sentence gets violated. Each was a real
finding, not a hypothetical.

---

## 1. Enumerate unfiltered, then scope — and state both numbers

The failure this prevents: a count of *what has been looked at* is mistaken for
*the population*. A sweep reports "all clean" over a set it silently narrowed.

Enumerate everything first, with no filter and no early exit:

```sh
gh api user/orgs --paginate --jq '.[].login'
gh api "orgs/$org/repos" -X GET -f per_page=100 -f type=all \
  --paginate --jq '.[] | {nameWithOwner:.full_name, private:.private,
                          archived:.archived, fork:.fork}'
```

Then apply scope as a **separate, named step**, and report both numbers: the
enumerated total and the in-scope subset, with the filter stated. "Public,
non-archived, excluding peer institutes" is a scope statement a reader can
check. "473 repos" alone is not.

**The filter goes after enumeration, never inside it.** Enumerating selectively
is how you get a number that cannot be audited, because the thing you excluded
left no trace. This is not a licence to enumerate less; it is the opposite.

Also worth knowing: the set of organizations an account belongs to is not the
set an automation sweeps. Those are usually different numbers, and a claim of
fleet coverage should say which one it means.

## 2. Give the instrument three values, not two

A probe that answers only *enabled* or *disabled* cannot tell you that the
setting **does not exist** on that target. That distinction was the entire
finding in one case here.

```sh
gh api "repos/$r" --jq '{
  ss:(.security_and_analysis.secret_scanning.status // "absent"), … }'
```

`// "absent"` turns a missing object into a reportable third value instead of
silently collapsing into "off". Concretely: a private repository returns **no
`security_and_analysis` object at all** — not one with the features disabled —
so "off" and "unavailable" would otherwise be indistinguishable, and a sweep
would report a gap where there is nothing to converge.

**Control the instrument before believing it.** Run a known-positive and a
known-negative through the same path. If a query returns zero, prove it can
return non-zero before treating the zero as a fact.

## 3. A 2xx is not evidence the write happened

The trap: an API accepts a field it does not support, returns success, and
ignores it. Nothing errors. `set -euo pipefail` does not fire. The job is green.
The state is unchanged.

Here, two repository settings were PATCHed onto hundreds of repositories with
every call returning 2xx, and **not one repository changed**. The features
required an entitlement the account did not have, and the API's response said
nothing about that.

**Read the state back after writing it**, whenever the write is the point of the
job. Then:

- do not count an unapplied change as applied — otherwise the "edits applied"
  figure is fiction;
- say why, once, in terms a reader can act on;
- keep the authored intent as-is. Recording the unreachable value as the
  *current* value would make the fleet read as converged while the setting is
  off everywhere — trading a loud gap for a silent one.

## 4. Probe an org-scoped fact once, not once per repository

The first version of the read-back guard above was correct and wasteful: it
re-proved the same organization-wide fact on **every** repository, spending an
extra write and read per repository per night to relearn one thing.

Probe once, set a flag, and have the remainder report the known cause without
issuing the calls. Then make the summary say the probe was not repeated —
otherwise the count reads as N failed writes rather than one cause affecting N
targets, and the fix invents a new false signal.

## 5. A safe mode that fails identically is not a safe probe

A convergence workflow had a policy gate that threw before it reached the code
path taking the `dry-run` flag. So `dry-run: true` failed **exactly** as the
real run did.

This matters more than it sounds. The obvious way to investigate a suspected
breakage is to re-run it in the tool's safe mode. Here that returned a failure
identical to the breakage and taught nothing — and would do the same for the
next person.

**When adding a preflight gate, check whether it runs before or after the
dry-run branch.** A gate ahead of it removes the ability to test anything
downstream of it, including whether the gate is the problem.

## 6. Unrelated concerns must not share a job

The same workflow ran policy enforcement as a step *before* the enumeration and
convergence steps in one job. When enforcement began failing — correctly,
against a real violation — every downstream step was skipped. Settings
convergence across the whole fleet stopped, and the only symptom was a red run
among other red runs.

**Split them into jobs with no dependency.** Both still fail loudly; neither
takes the other down. A policy opinion should not be able to silently disable an
unrelated mechanism, and if it can, the coupling is the defect — not the policy
and not the mechanism.

## 7. A declared key nothing reads is a silent no-op

Configuration schemas and the workflows that consume them drift apart. A key the
schema declares but no workflow reads has no effect and produces no error: the
person who authored it gets silence.

This repository has a guard asserting the two sets are identical, and it is
worth having. But see the next section for what it is and is not.

## 8. A detector is not a gate

The guard in §7 runs on no push and no pull request. Its only scheduled caller
is weekly, and it inspects the default branch. So a pull request introducing
exactly the drift it detects **merges green**, and the first look comes up to
seven days later.

That is still useful — but it is a *detector*, and calling it a gate overstates
it. A detector's value is bounded by whether anyone reads the signal; a gate's
is not.

Two consequences worth internalising:

- **"It passes in CI" may not be a statement about your change.** Check what ref
  the check reads and what triggers it before treating a green run as coverage
  of a pull request.
- **A check is not wired until something has been made to fail through the whole
  path it will actually run in** — not merely against a local fixture. A guard
  that has only ever been seen to pass, and has only ever been made to fail by
  hand, has an untested half.

## 9. Convergence files: absence is a value

Where a sweep derives desired state from a checked-in file, a **missing field is
not "leave it alone"** — it is usually "set it to empty".

If the sweep reads `.description // ""`, then authoring a file without a
description **wipes** the live description on the next run. The same applies to
any field with an empty-string or empty-list default. Two rules follow:

- **Derive values from live state rather than inventing them.** A field that
  already exists upstream is authoritative; copying it is non-destructive by
  construction, and inventing a plausible replacement is exactly how a sweep
  causes silent damage while reporting success.
- **Know which fields are safe to omit.** Omitting a list-valued field may strip
  what is there. Omitting it on a target that has nothing is a no-op. These are
  different situations and the file cannot tell you which one you are in.

Related: a file's mere absence can exclude a repository from a sweep entirely,
so it converges on *nothing* — not just on the setting being investigated. When
a sweep reports a repository as skipped, that is a coverage gap, not a pass.

## 10. Convergence repairs; mechanism questions are often academic

A number of repositories were found to have lost a setting they previously had.
The mechanism was never established — a plausible cause was identified and
explicitly recorded as inference rather than measurement.

It did not need to be established. Once the pipeline was working, the sweep
restored every affected repository. **A convergence loop that actually runs
makes the question "how did this drift?" much less urgent than "why did the loop
stop?"** Spend the investigation there.

When you do record a suspected cause, keep measurement and inference visibly
apart. A future reader cannot separate them later if the document does not.

## 11. The shell reports "ran and failed" and "ran and succeeded" identically

Added 2026-07-28, from a design session that had **read this register's companion
finding the day before and hit the same class of false green anyway**. That is the
argument for writing it here rather than in the document that occasioned it: this
lesson does not transfer by having been read once.

Three distinct instrument failures, all the same shape — *the probe answered a
question other than the one asked, and its answer looked like an answer.*

**A pipeline's exit status is the last stage's.** Reading a command's result
through `… | tail -5` reports `tail`'s status, not the command's. In this session
`swift package unedit` appeared to exit 0 while printing an error; re-run unpiped
it exits 1. The same trap had already produced a false green for a *failed build*
in a prior session, which is the more expensive direction — a build that failed
entered a record as passing.

> Never read an evidence-producing command's status through a pipe. Redirect to a
> file and read it, or set `-o pipefail`. **A green from a pipeline whose last
> stage is a pager is not a measurement of the first stage.**

**"Not found" and "nothing to search" are the same output.** A probe reported a
compiled marker absent from a build directory, which would have become the
finding *this mechanism does not work on that build system*. It was the
instrument: the path probed was a symlink into the real output directory, and
neither `find` nor `grep -r` descended it. What exposed it was a positive control
asking *can this probe find any known string here at all?* — which also came back
empty.

> Before believing a zero, make the instrument return non-zero **on the same
> path, in the same invocation shape**. A control run somewhere else proves the
> tool works, not that this probe was pointed at anything.

**Make the fixture's own failure visible in the result.** A baseline measurement
here reported its marker absent from compiled output three rounds running. Both
causes were the fixture — a missing `origin`, then manifests copied with absolute
URLs still pointing at the original — and neither was the finding. The only
reason a broken baseline did not become the headline number is that the
measurement printed the marker count beside every timing instead of printing a
duration alone.

> Report the evidence alongside the number, every round. A timing loop that
> prints only timings cannot distinguish *fast* from *did nothing*, and the
> second is much more common than it feels.

The connecting rule, which is §8's *"made to fail through the whole path"* applied
to measurement rather than to gates: **exit status attests that a process ran, never
that it was configured.** Between "the thing under test failed" and "the harness
failed to test it" the shell is silent, and it is silent in the direction that
looks like success.

---

## The shape underneath all of these

Three failures here compounded, and none was visible alone:

1. A setting was silently dropped on a set of repositories.
2. The mechanism that would have restored it died fifteen minutes later.
3. Both were invisible because each individual signal looked normal — a green
   convergence report, a red run among red runs, a successful API call.

What surfaced all three was measuring the population directly rather than
trusting any of the pipeline's own reports about itself.

**Trust a system's self-report only for things it cannot get wrong.** A workflow
saying `converged`, an API returning 2xx, and a green check are all claims made
by the thing under test. Verify them from outside, over the whole population,
with an instrument you have controlled.
