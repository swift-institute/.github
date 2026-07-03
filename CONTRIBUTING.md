# Contributing

Thank you for your interest in contributing to Swift Institute packages.

## Maintainer

Swift Institute packages are currently maintained by Coen ten Thije Boonkkamp
as a sole-contributor project. Contributions via pull request are welcome; all
PRs are reviewed by the maintainer before merging.

## Conventions

Development conventions — naming, errors, memory safety, testing, modularization,
and more — are maintained internally and applied during code review. Open a PR
against the relevant repository; the maintainer will surface any convention
considerations during review.

## Before opening a pull request

- Follow the conventions in the relevant skill
- Every new type needs a test. Every bug fix needs a regression test
- No Foundation imports in Primitives or Standards packages — Foundation is a
  Foundations-layer concern
- Run `swift build` and `swift test` before submitting
- Run `swift-format format --in-place .` before submitting (see *Development
  environment* below for the pinned wrapper that ensures local output matches CI)

## Development environment

CI runs `swift-format` from the `swift:6.3` Docker image. Local invocations
must use the same toolchain version, or `format --in-place` output will drift
from CI's strict-lint check and produce avoidable PR friction.

This repository ships a pinned wrapper at
`swift-institute/Scripts/swift-format` that exec's the matching standalone
toolchain. To use it, install a Swift 6.3.x toolchain from
[swift.org/install/macos](https://www.swift.org/install/macos/) and prepend the
Scripts directory to your `$PATH`:

```sh
# In ~/.zshrc, ~/.bashrc, or your shell's profile:
export PATH="$HOME/Developer/swift-institute/Scripts:$PATH"
```

After that, `swift-format` on the command line resolves to the pinned wrapper
and produces byte-identical output to CI. The rule and rationale live in the
ci-cd-workflows skill as `[CI-093]`.

## Running a single CI job on demand

The universal CI can be dispatched against one package, one job at a time, from
a central place — handy for reproducing a single failing leg without pushing to
the package. It is a **debug surface, not a gating surface**: runs appear in the
`swift-institute/.github` Actions tab, and they do not satisfy any branch
protection on the target.

```sh
gh workflow run ci-dispatch.yml -R swift-institute/.github \
  -f target-repo=<org>/<pkg> \
  -f job=linux-release \
  [-f ref=main]
```

`job` accepts one of the twelve dispatch-meaningful jobs (`macos-release`,
`linux-release`, `linux-nightly`, `windows-release`, `apple-simulator-build`,
`format`, `lint`, `swift-linter`, `lint-yaml`, `lint-broken-symlink`,
`lint-license-header`, `lint-test-support-spine`). See the header of
`.github/workflows/ci-dispatch.yml` for the full caveats.

## Code of Conduct

All participation in the Swift Institute ecosystem is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md). By contributing, you agree to abide by
its terms.

## Security

Do not report security vulnerabilities through public channels. Follow the
[Security Policy](SECURITY.md) for private reporting.

## License

By submitting a contribution, you agree that it will be licensed under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0), the license
used by all packages in the ecosystem.
