# Naming annex — Nest.Name normalization (controls spellings in the Fable 5 handoff)

Principal ruling: identifiers follow the Institute Nest.Name convention. The
parallel review's final edition adopted Nest.Name for public namespaces but
retained flat compound spellings for targets/modules (`InstituteReceipt`,
`CIContract`, `GitHubControl`). This annex normalizes every spelling to the
live house precedent (`Tools/repository-policy` → target directory
`Sources/Repository Policy/`, files `Repository.Policy.<Type>.swift`, public
types nested under noun namespaces). **Where the final edition and this annex
differ on a spelling, this annex controls.** Architecture, owners, boundaries,
gates, and the FT1→F18 order are unchanged.

## Package roots (unchanged boundaries, credential split preserved)

**Amended 2026-08-06 by principal ruling** (swift-institute/.github#404 comment
5208179754): package-root DIRECTORIES are kebab-case, matching the house
package-root precedent and the executable product each one carries. This
resolves swift-institute/Workspace#141 by rename rather than by exemption, so
the future Workspace directory validator ships exemption-free.

Target-directory spellings (spaces) and every type spelling in the next section
are UNCHANGED. This amendment moves the package-directory column only — the
directory boundary is chosen independently of the target and type boundaries,
and a kebab package root sits over spaced target directories without tension.

| Package directory | Package name | Executable products |
|---|---|---|
| `Tools/institute-ci` | Institute CI | `institute-ci` (thin front-end) |
| `Tools/institute-ci-control` | Institute CI Control | `institute-ci-control` (thin trusted front-end) |
| `Tools/repository-policy` | repository-policy | `repository-policy` |
| `Tools/pull-request-transaction` | pr-transaction | `pr-transaction` |

## Target and public-type spellings

| Final-edition flat spelling | Target name (house convention) | Public namespace / types | File pattern |
|---|---|---|---|
| RepositoryPolicy | `Repository Policy` (exists) | `Repository.Policy.*` | `Repository.Policy.<Type>.swift` |
| CIContract | `CI Contract` | `CI.Contract.*` (`CI.Contract.Plan`, `CI.Contract.Requirement`, `CI.Contract.AggregateVerdict`) | `CI.Contract.<Type>.swift` |
| InstituteReceipt | `Institute Receipt` | `Institute.Receipt.*` (`Institute.Receipt.Preterminal`, `Institute.Receipt.Terminal`, `Institute.Receipt.FailureClass`) | `Institute.Receipt.<Type>.swift` |
| InstituteCIApplication | `Institute CI Application` | `Institute.CI.Application.*` (use-case types) | `Institute.CI.Application.<UseCase>.swift` |
| InstituteCICommand | `Institute CI Command` | CLI mapping only; owns no predicate | `Institute.CI.Command.<Verb>.swift` |
| GitHubControl | `GitHub Control` | `GitHub.Control.*` (`GitHub.Control.Client`, `GitHub.Control.AppCredential`, `GitHub.Control.RetryPolicy`) | `GitHub.Control.<Type>.swift` |
| FleetInventory | `Fleet Inventory` | `Fleet.Inventory.*` (`Fleet.Inventory.Census`) | `Fleet.Inventory.<Type>.swift` |
| FleetConvergence | `Fleet Convergence` | `Fleet.Convergence.*` (`Fleet.Convergence.Plan`, `.Apply`, `.Resume`, `.Readback`) | `Fleet.Convergence.<Type>.swift` |
| PrivateVerification | `Private Verification` | `Private.Verification.*` (`.Request`, `.Envelope`, `.Verify`, `.Publish`) | `Private.Verification.<Type>.swift` |
| PullRequestTransaction | `PullRequest Transaction` | `PullRequest.Transaction.*` (`.Snapshot`, `.Verdict`, `.Receipt`) | `PullRequest.Transaction.<Type>.swift` |
| ProgrammePolicy | `Programme Policy` | `Programme.Policy.*` | `Programme.Policy.<Type>.swift` |
| InstituteCIControlApplication | `Institute CI Control Application` | `Institute.CI.Control.Application.*` | `Institute.CI.Control.Application.<UseCase>.swift` |
| InstituteCIControlCommand | `Institute CI Control Command` | CLI mapping only | `Institute.CI.Control.Command.<Verb>.swift` |

Notes:

1. Namespaces are caseless-nested enum nouns per the swift Skill; one type per
   file; typed throws via per-operation leaf errors
   (`Institute.Receipt.Terminal.ValidationError` style), per the standing
   leaf-error ruling.
2. Target names with spaces follow the existing `Repository Policy` precedent;
   FT1 ratifies the exact manifest spellings (module aliasing where the
   toolchain requires) — a toolchain constraint discovered at FT1 is a
   spelling stop, never a licence to revert to flat compounds.
3. Executables stay kebab-case (`workspace` precedent).
4. Workspace-side additions keep Workspace's own conventions
   (`Workspace.Inventory.Effective.*`, routing projection under
   `Workspace.CI.Routing.*`).
5. Generated artifacts (leaf callers, routing rows, schemas) are projections
   and carry no Swift spelling; their generator types follow this annex.

## Handoff rule

The Fable 5 handoff = (1) the parallel review's final edition (architecture,
transactions FT1→F18, stops, canaries) + (2) this annex (spellings) + (3) the
principal's move-fast posture (Addendum 4: single measured cutovers, deletion
joins activation, no compatibility surfaces; safety/evidence rules unwaived).
FT1's ratification output must restate the full target/product/type table in
these spellings before F1 begins; the /github work objects created for the
programme must quote spellings from this annex only.
