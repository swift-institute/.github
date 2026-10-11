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
- Run `xcrun swift-format format --in-place --recursive .` before submitting
  (see *Development environment* below)

## Development environment

CI formats and lints with the `swift-format` that ships with Xcode 27.1
(27A9269). Select that Xcode (`xcode-select -s /Applications/Xcode.app`) and
run `xcrun swift-format`, so local output matches CI byte for byte.

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

`job` accepts one of the thirteen dispatch-meaningful jobs (`macos-release`,
`linux-release`, `linux-nightly`, `linux-6-4`, `windows-release`,
`apple-simulator-build`, `format`, `lint`, `swift-linter`, `lint-yaml`,
`lint-broken-symlink`, `lint-license-header`, `lint-test-support-spine`).

There are two independent ref knobs, easy to conflate:

- `-f ref=<branch>` — the **target** ref: which commit of `target-repo` is
  checked out and built. Defaults to `main`.
- `--ref <branch>` — the **CI-definition** version: which revision of
  `ci-dispatch.yml` / `swift-ci.yml` actually runs. Defaults to the default
  branch of `swift-institute/.github`.

The surface is public-target-only by design. See the header of
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
