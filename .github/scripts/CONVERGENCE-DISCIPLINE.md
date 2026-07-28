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

**The general form, and the sentence to remember: the probe that reports "not
found" and the probe that reports "nothing to search" produce identical output.**
Nothing in a zero tells you which one you got.

> Before believing a zero, make the instrument return non-zero **on the same
> path, in the same invocation shape**. A control run somewhere else proves the
> tool works, not that this probe was pointed at anything.

**Check the predicate before you check the timing.** When an enumerator misses
something, the tempting explanation is that the snapshot fell in a gap. Usually it
is the pattern: a predicate built from what you expected to find cannot match what
you did not expect. `pgrep -f "workspace package build"` cannot match a bare
`swift build` anywhere, at any moment, under any load.

The reliable form takes no pattern from expectation — enumerate by exact process
name, then resolve each one:

```sh
{ pgrep -x swift-build; pgrep -x swift-frontend; } | sort -u | while read p; do
  lsof -a -p "$p" -d cwd -Fn | grep ^n | cut -c2-
done
```

**And resolve *every* result before characterising any of them.** A related failure
in the same session had a sound predicate: it captured four processes, then
reported whose they were after resolving only two. The unresolved entries were
described from their command lines alone, and one of them was misattributed. **A
population you enumerated but did not resolve is not evidence about that
population** — partial resolution reads exactly like full resolution in the
write-up.

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

## 12. A control that passes for the wrong reason is not a control

Same session, and the sharper half of §11 because here the *negative* control was
the thing that lied.

A test asserted that a build could succeed offline only because a local-source
overlay was active. Its negative control removed the overlay and expected failure.
**It returned success** — and the reason was a second cache nobody had cleared:
removing the overlay restored working copies from a build-directory checkout cache
that survived both the removal and the deletion of the remotes, so the build
succeeded from warm canonical source.

What caught it was not the exit status. It was that the test also asserted *which
source got compiled*, and the canonical marker appeared where the local one should
have been.

> **Assert the mechanism, not just the outcome.** A control that only checks
> pass/fail cannot tell "the thing I removed was load-bearing" from "something else
> supplied it." Check *what* was produced and *from where*.

> **Enumerate every cache the claim depends on, not the one you were thinking
> about.** Here there were three — the resolved-pins file, the build directory, and
> a checkout cache inside it — and clearing two of the three produced a confident
> green that meant nothing.

### The cache list, because "clean" here means four things

Found the same day, in the same session, by a separate experiment. Any claim in
this programme about **clean**, **offline**, or **reverted** SwiftPM state has to
clear all four:

| Cache | Cleared by | Survives |
|---|---|---|
| Resolved pins | `rm Package.resolved` | everything else |
| Build directory | `rm -rf .build` | `swift package clean` |
| Checkout cache | `rm -rf .build/checkouts` | `unedit`, and removal of the remotes |
| **Shared manifest cache** | `--manifest-cache none` | **all of the above, plus `resolve`** |

The shared manifest cache lives outside the package entirely
(`~/Library/Caches/org.swift.swiftpm/manifests`, 144 MB on the machine where this
was found), so nothing done inside a checkout touches it.

### And the trap that made it matter: content-keyed caches versus ambient-state inputs

> **A manifest whose evaluation depends on ambient filesystem state is unreliable
> under a content-keyed cache.** The cache key is the manifest's *bytes*. It cannot
> see the input the manifest actually read, so changing that input changes nothing.

Concretely: a package manifest was made to switch between two dependency sources
depending on whether a marker file existed. Creating the marker switched it **on**.
Deleting the marker did **not** switch it off — and neither did touching the
manifest, nor an explicit `resolve`. It kept resolving the wrong way until the
manifest cache was disabled, which is what turned a hypothesis into a diagnosis.

The failure direction is the dangerous one: the operator believes they have
**turned the special mode off** and has not. Anyone reaching for a
conditionally-evaluating manifest — a build flag, a marker file, a hostname check —
will hit this. An input the cache key does not include is an input the cache will
ignore.

Worth knowing for contrast: an *environment variable* read by the same manifest
reverted correctly in both directions, because SwiftPM's key accounts for it. That
is a distinction between two undocumented behaviours, not a rule to rely on — the
lesson is to test **both directions** of any toggle, not to trust the one that
happened to work.

### A fourth instance, where the fixtures themselves were the broken instrument

Found the same day by the validator-sweep session, and worth recording because the
failing component was the *control apparatus*, not the thing under test.

A new guard shipped with five fixture scenarios — one `pass/`, four `fail/`. Run
locally, every one behaved: `pass/` exited 0, all four `fail/` exited 1. That is
exactly the result a working positive control produces.

The four `fail/` scenarios were exiting 1 because the guard **crashed on import**.
It annotated a helper `-> list[str] | None`, which the runner's **Python 3.9**
evaluates at function-definition time and rejects with `TypeError: unsupported
operand type(s) for |`. The script died before reading a single fixture.

So the four controls "passed" — a non-zero exit is a non-zero exit — while
measuring nothing at all. The only reason it surfaced is that the harness printed
each scenario's *output* alongside its exit code, and the `pass/` scenario, which
must exit 0, was visibly red for the same reason.

> **An exit status is not a verdict.** For a `fail/` fixture, "the checker
> reported a violation" and "the checker could not start" are the same number.
> Assert on the *finding*, or at minimum print what the check said, so a crash
> cannot wear a control's clothes.

The `pass/` fixture did all the work here. A suite of only `fail/` scenarios would
have been uniformly, confidently green — every control firing, nothing measured.
**A control set needs at least one member whose expected result is the one a
crash cannot produce.**

## 13. Wall clocks are contaminated by load; sums of reported per-item timings are not

A measurement on a shared machine returned **329 s**, then **148 s** for the same
command in the same state — a 2.2× spread, reported to a reviewer as a single
figure before the second run existed. The cause was concurrent work from other
sessions that was neither controlled nor recorded, and the script that took the
measurement carried a comment asserting the machine was "otherwise quiet" while it
was not.

Three rules, in order of how much they save:

> **A comment asserting a condition is not a measurement of that condition.** If a
> run's validity depends on the machine being quiet, sample the load and print it
> beside the number.

> **Distinguish measurements contention can corrupt from those it cannot.** An
> end-to-end wall clock is corrupted by load. A *sum of per-item timings the tool
> itself reports* is not — load inflates the parts and the whole together, so
> ratios and decompositions survive a run whose total does not. This is the
> difference between discarding a whole run and discarding part of one.

> **For shape, hold conditions constant rather than quiet.** When the question is
> "does cost grow linearly or worse", take every point back to back under whatever
> load exists and record it. Shape survives contention that would destroy an
> absolute figure — and shape is usually what gates the decision.

And the disposal rule: **kill a single uncontrolled number before it hardens.** A
figure quoted once becomes a citation, and a citation becomes a premise. Publish
the range with its conditions, and say which end you trust and why.

---

## 14. A working copy is a cache of the repository, and it goes stale silently

Found 2026-07-28, after two sessions independently ruled from a checkout that
was **12 commits behind `origin/main`**.

The failure is not carelessness — both sessions did the right thing. One was
told a rule second-hand and, rather than trusting the relay, opened
`Skills/github/SKILL.md` and read it. The file was there, it parsed, it said
what the relay said. It was also two hours out of date: a commit that morning
had deleted the clause being enforced and reversed the guidance on an adjacent
one.

The consequences were real and asymmetric:

- A rule that **no longer existed** was enforced against another session twice,
  producing a delete-and-re-file cycle for three legitimate issues.
- Board fields were set on three items from a vocabulary deleted that morning,
  making them the **only 3 classified rows out of 103** — the exact outcome the
  current text warns against.
- Two other skills had been rewritten in the same window, one of which had
  already been used to brief a third session. Those rules happened to survive
  the rewrite. **That was luck, not diligence**, and it is the reason this is a
  method note rather than an incident report.

> **Reading the source yourself is not the control. Reading the *current*
> source is.** A stale working copy is indistinguishable from the repository:
> same path, same filename, valid content, no warning anywhere in the output.

What makes this worse than an ordinary cache is that the staleness is
**invisible at the point of use and silent at the point of decision**. Nothing
in `cat SKILL.md` says "12 commits behind". Compare §12: the control passed and
the reason was a second cache nobody had cleared. Same shape, one layer out —
here the cache is the checkout itself.

Cheap habits that close it:

```sh
git -C <repo> fetch -q origin && git -C <repo> rev-list --count HEAD..origin/main
gh api repos/<owner>/<repo>/contents/<path> --jq .content | base64 -d
```

The first reports staleness as a number; the second bypasses the working copy
entirely and is the right instrument when a decision rests on the file's exact
current text. Both were used to establish the facts above.

**And do not fix it by pulling someone else's checkout.** Where several sessions
share a tree, `git pull` over another actor's uncommitted work is the
destructive operation the shared-checkout rules exist to prevent. Read from
`origin` or from your own clone; leave the shared tree alone. *Measured after
the fact: the checkout above was current again within the hour, which is the
other half of the problem — a hazard that resolves on its own teaches nobody,
and returns.*

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
