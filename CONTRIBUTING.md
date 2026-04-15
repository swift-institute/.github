# Contributing

Thank you for your interest in contributing to Swift Institute packages.

## Maintainer

Swift Institute packages are currently maintained by Coen ten Thije Boonkkamp
as a sole-contributor project. Contributions via pull request are welcome; all
PRs are reviewed by the maintainer before merging.

## Conventions

Development conventions — naming, errors, memory safety, testing, modularization,
and more — are defined in the [`Skills/`](https://github.com/swift-institute/swift-institute/tree/main/Skills)
directory of the [swift-institute](https://github.com/swift-institute/swift-institute)
meta-repository. Each skill is the canonical source for its area.

## Before opening a pull request

- Follow the conventions in the relevant skill
- Every new type needs a test. Every bug fix needs a regression test
- No Foundation imports in Primitives or Standards packages — Foundation is a
  Foundations-layer concern
- Run `swift build` and `swift test` before submitting

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
