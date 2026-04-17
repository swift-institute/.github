# Swift Institute

A layered Swift package ecosystem organized around shared conventions.

## What this is

Swift Institute is a set of layered Swift packages organized as separate GitHub
organizations, one per layer. The layers share dependency rules, naming
conventions, error handling, memory ownership, and API shape — so that
compile-time guarantees hold across the entire stack rather than stopping at
package boundaries.

| Layer | Organization | Role |
|-------|--------------|------|
| 1 | [swift-primitives](https://github.com/swift-primitives) | Atomic building blocks — buffer, geometry, algebra, memory, kernel |
| 2 | [swift-standards](https://github.com/swift-standards) + per-authority orgs | Specification implementations |
| 3 | [swift-foundations](https://github.com/swift-foundations) | Composed building blocks — IO, HTML, CSS, SVG, PDF, networking |
| 4 | Components | Opinionated assemblies — planned |
| 5 | Applications | End-user systems — planned |

> **Release in progress.** The organization links above are being made world-readable over the coming weeks. Some may currently 404; they resolve as each layer's release lands.

Layer 2 is an organization of organizations. Each standards authority has its
own GitHub organization hosting the packages it governs:
[swift-ietf](https://github.com/swift-ietf) (RFCs),
[swift-iso](https://github.com/swift-iso),
[swift-w3c](https://github.com/swift-w3c),
[swift-whatwg](https://github.com/swift-whatwg),
plus single-package organizations for IEEE, IEC, ECMA, INCITS, ARM, Intel,
RISC-V, and Microsoft.

## Where to go next

| If you want to... | Go to |
|-------------------|-------|
| Read the website, architecture overview, or blog | [swift-institute.org](https://swift-institute.org) |
| Use atomic primitives (buffer, geometry, algebra, memory, kernel) | [swift-primitives](https://github.com/swift-primitives) |
| Consume an RFC or ISO specification | [swift-ietf](https://github.com/swift-ietf), [swift-iso](https://github.com/swift-iso), or the relevant per-authority org |
| Use composed building blocks (IO, HTML, CSS, SVG, PDF) | [swift-foundations](https://github.com/swift-foundations) |
| Browse design rationale | [swift-institute/Research](https://github.com/swift-institute/Research) |
| Browse the empirical receipts behind technical claims | [swift-institute/Experiments](https://github.com/swift-institute/Experiments) |
| Report an issue or contribute | Open an issue or pull request on the relevant repository |
| Report a security vulnerability | See the [security policy](https://github.com/swift-institute/.github/blob/main/SECURITY.md) |

## Status

Initial public alpha. The website ([swift-institute.org](https://swift-institute.org))
and companion repositories ([Research](https://github.com/swift-institute/Research),
[Experiments](https://github.com/swift-institute/Experiments)) are public.
The package layers they describe are being released repository by repository
over the coming weeks.

Maintained by [Coen ten Thije Boonkkamp](https://github.com/coenttb) —
contributions welcome via pull request.

## License

All packages use the Apache License 2.0.
