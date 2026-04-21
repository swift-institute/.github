# Governance

This document describes how the Swift Institute organization makes decisions,
accepts contributions, and maintains its packages. It supplements
[`CONTRIBUTING.md`](CONTRIBUTING.md) (how to contribute) and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) (community norms).

## Mission

Swift Institute publishes timeless infrastructure for Swift: atomic
primitives, specification-mirroring standards, and composable foundations.
Every decision is treated as permanent — APIs are expected to outlive the
session that produced them.

## Maintainership model

The organization is maintained as a sole-contributor project by
[Coen ten Thije Boonkkamp](https://github.com/coenttb) (BDFL-style). The
maintainer is the final decision-maker on API shape, architectural direction,
release scope, and inclusion of new packages.

This model is stated explicitly so contributors know what to expect; it is
not a permanent commitment. Contributor growth that warrants a formal
steering arrangement is a welcome problem and will update this document.

## Decision authority

Architectural and API decisions follow the rules recorded in the
[Skills](https://github.com/swift-institute/Skills) repository. Skills are
the canonical source for naming, error handling, memory safety,
modularization, testing, and related conventions. They override memorized
patterns, precedent from other projects, and ad-hoc preferences in any given
review.

When a proposed change is not covered by an existing skill, the maintainer
decides. If the decision establishes a durable rule, the corresponding skill
is updated so the rule is recorded for future contributors.

## Contribution flow

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full guide. In brief:

- **Open an issue first** for non-trivial changes — new APIs, refactors,
  package additions, architectural moves. An early scope discussion prevents
  wasted implementation effort.
- **Follow the skills.** Convention compliance is not optional; the standard
  is "timeless infrastructure."
- **One focused change per pull request.** Unrelated improvements get their
  own PR.
- **Tests required.** Every new type needs a test; every bug fix needs a
  regression test.

## Release and versioning

- Each package publishes its own semantic-version tags. Patch and minor
  releases land as changes accumulate. Major releases are infrequent and
  are preceded by an explicit scope discussion.
- The maintainer cuts releases. Release artifacts and DocC archives are
  produced by the shared CI workflows in
  [`swift-institute/.github`](https://github.com/swift-institute/.github).

## Becoming a maintainer

The organization is not currently accepting additional maintainers. As the
contributor base grows, this section will be updated with an explicit
onboarding path — demonstrated track record on skills compliance, depth of
contribution, and alignment with the mission are the factors that will
apply.

## Enforcement

Violations of the [Code of Conduct](CODE_OF_CONDUCT.md) and security
concerns are handled by the maintainer. Reporting channels and private
disclosure procedures are documented in [`SECURITY.md`](SECURITY.md) and
the Code of Conduct.

## Amendments

The maintainer may amend this document. Substantive changes are announced
on the organization's public channels.
