# Swift Institute

A layered Swift package ecosystem organized around shared conventions.

The public contributor front door is
[swift-institute/Workspace](https://github.com/swift-institute/Workspace): clone it for the
package inventory, setup instructions, synchronization tooling, and checkout diagnostics.

## Why

Rules sit at the heart of every system we build on. When rules are expressed clearly and consistently, everything built on top of them becomes simpler, safer, and more predictable. We believe rules deserve a form that can be validated rather than interpreted — and Swift's type system makes that possible.

Swift Institute applies that idea to infrastructure itself: specifications become types, conventions become compiler guarantees, and the same discipline runs from the smallest buffer primitive to a complete PDF renderer.

## How it is organized

The ecosystem spans GitHub organizations for four package layers. Dependencies point down
only, and packages are converging on shared dependency, naming, typed-error, memory-ownership,
and API-shape conventions.

| Layer | Organization | Role |
|-------|--------------|------|
| 1 | [swift-atoms](https://github.com/swift-atoms) | Atoms — what must exist |
| 2 | [swift-molecules](https://github.com/swift-molecules) | Molecules — what is built from atoms alone: buffers, memory, async, parsing, trees |
| 3 | [swift-standards](https://github.com/swift-standards) + per-authority orgs | Specification implementations — RFC, ISO, W3C, WHATWG |
| 4 | [swift-compositions](https://github.com/swift-compositions) | Composed systems — I/O, filesystem, HTML, CSS, PDF, networking |

Layer 3 is an organization of organizations: each standards authority has its own GitHub organization — [swift-ietf](https://github.com/swift-ietf) (RFCs), [swift-iso](https://github.com/swift-iso), [swift-w3c](https://github.com/swift-w3c), [swift-whatwg](https://github.com/swift-whatwg), plus single-package organizations for IEEE, IEC, ECMA, INCITS, ARM, Intel, RISC-V (pending), and Microsoft.

## Where to go next

| If you want to... | Go to |
|-------------------|-------|
| Set up the ecosystem or inspect its public package inventory | [Workspace](https://github.com/swift-institute/Workspace) |
| Use atomic building blocks | [swift-atoms](https://github.com/swift-atoms) and [swift-molecules](https://github.com/swift-molecules) |
| Consume an RFC, ISO, W3C, or WHATWG specification | [swift-standards](https://github.com/swift-standards) |
| Use composed systems (I/O, filesystem, HTML, CSS, PDF) | [swift-compositions](https://github.com/swift-compositions) |
| Call the reusable CI workflows | [.github/workflows](https://github.com/swift-institute/.github/tree/main/.github/workflows) — pin an immutable SHA; not formally supported outside the ecosystem |
| Report a security vulnerability | [Security policy](https://github.com/swift-institute/.github/blob/main/SECURITY.md) |
| Report an issue or contribute | Open an issue or pull request on the relevant repository |

## Status

Public alpha. The realised layer organizations are public and packages continue to land repository by repository; APIs may change until first tagged releases.

Swift Institute is an independent open-source project, not affiliated with Apple or the Swift open-source project.

Maintained by [Coen ten Thije Boonkkamp](https://github.com/coenttb) — contributions welcome via pull request.

## License

Policy requires Apache License 2.0 for packages in the three realised layers. The public fleet is
being reconciled against that policy; until that work is complete, each repository's `LICENSE`
file is the authority for that repository.
