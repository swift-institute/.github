# Swift Institute

A layered Swift package ecosystem organized around shared conventions.

## Why

Rules sit at the heart of every system we build on. When rules are expressed clearly and consistently, everything built on top of them becomes simpler, safer, and more predictable. We believe rules deserve a form that can be validated rather than interpreted — and Swift's type system makes that possible.

Swift Institute applies that idea to infrastructure itself: specifications become types, conventions become compiler guarantees, and the same discipline runs from the smallest buffer primitive to a complete PDF renderer.

## How it is organized

The ecosystem is a set of GitHub organizations, one per layer. Layers depend downward only, and every package shares the same dependency rules, naming conventions, typed error handling, memory-ownership discipline, and API shape — so compile-time guarantees hold across the entire stack rather than stopping at package boundaries.

| Layer | Organization | Role |
|-------|--------------|------|
| 1 | [swift-primitives](https://github.com/swift-primitives) | Atomic building blocks — buffer, memory, geometry, time, async |
| 2 | [swift-standards](https://github.com/swift-standards) + per-authority orgs | Specification implementations — RFC, ISO, W3C, WHATWG |
| 3 | [swift-foundations](https://github.com/swift-foundations) | Composed systems — I/O, filesystem, HTML, CSS, PDF, networking |
| 4 | Components — planned | Opinionated assemblies |
| 5 | Applications — planned | End-user systems |

Layer 2 is an organization of organizations: each standards authority has its own GitHub organization — [swift-ietf](https://github.com/swift-ietf) (RFCs), [swift-iso](https://github.com/swift-iso), [swift-w3c](https://github.com/swift-w3c), [swift-whatwg](https://github.com/swift-whatwg), plus single-package organizations for IEEE, IEC, ECMA, INCITS, ARM, Intel, RISC-V, and Microsoft.

## Where to go next

| If you want to... | Go to |
|-------------------|-------|
| Read the website, architecture overview, or blog | [swift-institute.org](https://swift-institute.org) |
| Use atomic primitives | [swift-primitives](https://github.com/swift-primitives) |
| Consume an RFC, ISO, W3C, or WHATWG specification | [swift-standards](https://github.com/swift-standards) |
| Use composed systems (I/O, filesystem, HTML, CSS, PDF) | [swift-foundations](https://github.com/swift-foundations) |
| Browse design rationale | [Research](https://github.com/swift-institute/Research) |
| Browse the experiments behind technical claims | [Experiments](https://github.com/swift-institute/Experiments) |
| Call the reusable CI workflows | [.github/workflows](https://github.com/swift-institute/.github/tree/main/.github/workflows) — pin an immutable SHA; not formally supported outside the ecosystem |
| Report a security vulnerability | [Security policy](https://github.com/swift-institute/.github/blob/main/SECURITY.md) |
| Report an issue or contribute | Open an issue or pull request on the relevant repository |

## Status

Public alpha. All layer organizations are public and packages continue to land repository by repository; APIs may change until first tagged releases.

Maintained by [Coen ten Thije Boonkkamp](https://github.com/coenttb) — contributions welcome via pull request.

## License

All packages use the Apache License 2.0.
