# Census: `Packages/` and `Package.resolved` ignore posture

Measured 2026-07-28, as an independent second take on a census produced by the
SPM-edit overlay design session. A census taken by one session and confirmed by
another is worth more than either alone — and this one **does not fully
reproduce**, which is the more useful outcome.

Committed here rather than tracked as an issue; issues are ruled out as a
durable location this phase.

---

## Why it matters

`swift package edit` writes a symlink under `Packages/`. Where that directory is
not ignored, an editable-state symlink is **committable** — a local development
posture can be pushed by accident and then resolved by everyone else.

---

## Instrument

Asked **git**, not the file. The authoritative question is not "does
`.gitignore` contain a line matching `Packages`" but "would git ignore this
path", so each repository was queried with:

```sh
git check-ignore -q "Packages/"          # ignore posture
git check-ignore -q "Package.resolved"
git ls-files --error-unmatch Package.resolved   # actually tracked?
```

**The trailing slash is load-bearing.** A first control run used
`git check-ignore .build` against a repository whose `.gitignore` contains
`.build/`, and got "not ignored" — because a pattern with a trailing slash
matches directories only, and the path as written signalled no directory. The
instrument was right and the control input was wrong. Without the control that
would have been a false census reporting hundreds of repositories as
non-ignoring.

Control, after correction, in a single repository:

| Path | Result |
|---|---|
| `.build/` | ignored (rc 0) |
| `Package.resolved` | ignored (rc 0) |
| `Packages/` | not ignored (rc 1) |
| `README.md` | not ignored (rc 1) |

Both values obtainable, so a 0 or a 1 from this instrument means something.

Every disagreement below was then re-checked **against the live GitHub API**,
fetching `.gitignore` and the tree directly rather than trusting the local
clone.

## Population

Public, non-archived, in the 17 active orgs, having a `Package.swift`:
**450 packages** (from 473 public non-archived repositories, from 664
enumerated unfiltered).

The overlay session reported 441. The 9-package difference is unreconciled —
most likely a different scope filter — and does not affect the disagreements
below, all of which were confirmed individually.

---

## Result

| Property | Count |
|---|---:|
| Packages examined | 450 |
| **Not ignoring `Packages/`** | **11** |
| Not ignoring `Package.resolved` | 2 |
| `Package.resolved` actually tracked | 1 |

### The 11 not ignoring `Packages/`

```
swift-foundations/swift-image-magick
swift-foundations/swift-money
swift-foundations/swift-resource-pool
swift-foundations/swift-server-dependencies
swift-foundations/swift-sitemap
swift-foundations/swift-structured-queries-postgres      <- not in the first census
swift-foundations/swift-svg-printer
swift-institute/Issues                                   <- not in the first census
swift-institute/pointfree-url-form-coding                <- not in the first census
swift-institute/swift-web-foundation                     <- not in the first census
swift-primitives/swift-percent-primitives
```

---

## Where the two censuses disagree

**Seven of the first census's eight reproduce exactly.** The differences:

### One false positive: `swift-foundations/swift-authentication`

It **does** ignore `Packages/`. Confirmed three independent ways: the line in
the local clone's `.gitignore`, `git check-ignore -v` resolving to
`.gitignore:55:Packages/`, and the file fetched fresh from the API.

Checked for a timing artifact, because that was the charitable explanation: the
entry was added in **`ba278ed`, 2026-07-21** — *"Ignore Packages/ (edit-mode
posture, relay 5)"* — a week before either census. It was already ignored when
the first census ran, so this is a false positive rather than a stale reading.

### Four missed: four more repositories are non-ignoring

`swift-structured-queries-postgres`, `swift-web-foundation`,
`pointfree-url-form-coding`, and `Issues` all lack any `Packages/` entry,
verified against the live API rather than the local clones.

Two of them, `pointfree-url-form-coding` and `Issues`, are unusual repositories —
a vendored fork and a non-library package — which is a plausible reason a census
scoped differently would not have reached them.

### The `Package.resolved` claim does not hold

The first census reported `Package.resolved` ignored **and** untracked in all
441. In this population, two exceptions:

- **`swift-institute/fork-swift-parsing`** — `Package.resolved` is **tracked**,
  and its `.gitignore` does not mention it. Confirmed present in the remote
  tree. This is a verbatim fork of `pointfreeco/swift-parsing`, and tracking a
  resolved file is normal upstream practice, so it is plausibly correct rather
  than a defect — see the vendored-fork question in
  `SWEEP-FINDINGS-2026-07-28.md`, which is the same underlying decision.
- **`swift-institute/swift-protocol-mirror`** — not ignored, but also not
  present, so nothing is currently committed. A latent gap rather than a live
  one.

---

## Disposition

Uniformity defect; the fix is small and mechanical (add `Packages/` to eleven
`.gitignore` files) and is **not claimed by this session**.

Whoever takes it should settle `fork-swift-parsing` deliberately rather than
sweeping it in: forcing Institute ignore posture onto vendored upstream code is
the same trade recorded in `SWEEP-FINDINGS-2026-07-28.md`, and it should be
decided once for both.

## Method note worth keeping

Both censuses were honest and one had a false positive and four misses. What
separated them was not care but **instrument choice**: asking `git check-ignore`
rather than pattern-matching `.gitignore` text, and re-verifying every
disagreement against the live API instead of the local copy. A grep for
`Packages` in `.gitignore` would have agreed with whichever census ran it.
