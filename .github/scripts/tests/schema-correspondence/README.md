# GH-REPO-063 correspondence fixtures

These sit beside `fixtures/`, not inside it, on purpose.

The fixture harness walks `fixtures/<rule-id>/{pass,fail,edge}/<scenario>/`
as repository-shaped subjects, counting findings by their TSV rule prefix.
This guard takes three *file* paths — each scenario here is the trio flat in
one directory — so registering it there would have meant adding a second
execution mode to a runner whose single convention is the reason it is
readable. Placing the fixtures under `fixtures/` without registering them was
not an option either: the harness fails on an unowned rule directory, and it
was right to.

F16 port: the guard is Swift-owned — `CI.Validation.SchemaCorrespondence` in
`Tools/institute-ci`, retiring `validate-schema-workflow-keys.py`. Its
`--schema/--sync-workflow/--readme-validator` face carries the same
three-file shape, and `Tools/institute-ci/Tests/CI Validation Tests` runs
every scenario below in-process. These fixtures are corpus DATA, pinned by
exact membership in the ManifestBinding stub guard; they are not edited
alongside the validator.

They are also executed by `.github/workflows/validate-schema-correspondence.yml`,
which runs every scenario on every push and pull request touching the
correspondence, and treats "found no scenarios" as a failure rather than a pass.

Each scenario is a self-contained trio standing in for the three real files:

| file | stands in for |
|---|---|
| `metadata-schema.json` | the repo-root schema |
| `sync-metadata.yml` | `.github/workflows/sync-metadata.yml` |
| `validate-readme.py` | `.github/scripts/validate-readme.py` |

| scenario | what it proves |
|---|---|
| `pass/consistent` | all three correspondences agreeing exits 0 |
| `fail/settings-key-unread` | the original 2026-07-03 defect: a schema key no workflow reads |
| `fail/readme-exempt-unhandled` | an `exempt` enum value absent from `EXEMPTIONS` — previously unchecked by any machine |
| `fail/readme-family-unhandled` | the same shape on `family` / `FAMILIES` |
| `fail/constant-renamed` | the guard fails closed when it cannot FIND a constant, rather than reading absence as agreement |

Each `fail/` scenario was watched to fire, and each was mutation-tested: with
the readme correspondence neutered the three readme scenarios go green, and with
the fail-closed branch removed `constant-renamed` goes green. A fixture that
survives every mutation of the thing it guards is decorative.
