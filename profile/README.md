# Swift Institute

A layered Swift package ecosystem: specifications become types, conventions become compiler checks, and one discipline runs from the smallest buffer to a PDF renderer. This page is the entry point for people and agents alike. To bind a project to the Institute, add one line to its agent instructions (`CLAUDE.md`, `AGENTS.md`): *Before changing code here, read https://github.com/swift-institute in full and follow it.*

Every rule a machine can check lives in that check, not here: the lint rules in [institute](https://github.com/swift-institute/institute), `institute ci -- package validate` over the package graph, SwiftPM and the compiler, and GitHub's own settings and rulesets. A finding names its rule. What follows is what no check can say.

## Organizations

`swift-institute` is the control organization: policy, CI and tooling, and no layer. It governs four layer organizations, and their public repositories are the fleet. An organization's layer is `Institute.Organization` in [institute](https://github.com/swift-institute/institute); never infer a layer from a package name. A repository that deviates from the uniform CI says so in its own `.github/metadata.yaml` (`platforms:`, `embedded-target:`, `ci:`).

| Layer | Organization | Holds |
|---|---|---|
| 1 Atoms | [swift-atoms](https://github.com/swift-atoms) | What must exist |
| 2 Molecules | [swift-molecules](https://github.com/swift-molecules) | What is built from atoms alone: buffers, memory, async, parsing, trees |
| 3 Standards | [swift-standards](https://github.com/swift-standards) and the authority organizations | What is specified externally: RFC, ISO, W3C, WHATWG |
| 4 Compositions | [swift-compositions](https://github.com/swift-compositions) | What composes beyond that, and every opinion: I/O, filesystem, HTML, CSS, PDF, networking |

Layer 3 is an organization of organizations. Each authority has its own: [swift-ietf](https://github.com/swift-ietf) (`swift-rfc-{number}`), [swift-iso](https://github.com/swift-iso) (`swift-iso-{number}`), [swift-ieee](https://github.com/swift-ieee), [swift-iec](https://github.com/swift-iec), [swift-w3c](https://github.com/swift-w3c), [swift-whatwg](https://github.com/swift-whatwg), [swift-ecma](https://github.com/swift-ecma), [swift-incits](https://github.com/swift-incits), [swift-bipm](https://github.com/swift-bipm), [swift-linux-foundation](https://github.com/swift-linux-foundation), and the vendors [swift-arm-ltd](https://github.com/swift-arm-ltd), [swift-intel](https://github.com/swift-intel), [swift-riscv](https://github.com/swift-riscv) and [swift-microsoft](https://github.com/swift-microsoft). swift-standards itself holds the policy-free convergence packages, `swift-{concept}-standard`, which absorb spec revisions so consumers never change. One spec can carry two designations (IEEE 1003.1 is ISO/IEC 9945); such packages split the spec by surface and are not duplicates. Local checkouts nest the same way, with the authority folders inside the swift-standards folder.

Older text says Primitives for layers 1 and 2 and Foundations for layer 4; neither organization exists.

## Placement and direction

Can you point to an external spec, man page or SDK document that defines this surface? Yes: layer 3. No: layer 1 if it is an atomic prerequisite, layer 2 if it is built from atoms alone, layer 4 otherwise. An extraction without a clear answer goes to swift-compositions.

Dependencies point down: atoms on atoms; molecules on atoms and molecules; standards on atoms, molecules and standards; compositions on anything; products, which live outside the Institute, on all of it. The lower a package sits, the more it is perfected on its own terms, and everything above it bends to fit. What the check cannot decide:

- **A package is finished to its own laws.** It is designed around the concept it names, never around what one consumer needs. No app, product or higher package shapes a lower one.
- **A general idea lives at the lowest layer its dependencies allow, now.** Layer follows essence, never the current edges or the current home. When part of a higher package is a general concept (an exact rate, a floor, a PSNR), it moves down in the same piece of work; waiting for a second consumer is deciding from downstream. When an edge points up, the capability moves down; the consumer never lifts. This is about where existing code lives, not about building what nothing uses yet.
- **A gap is fixed where it is.** Every capability has one owner; everything else composes it. A helper in a higher package that makes up for something missing below is a defect in the lower package: file it there, fix it there, then delete the helper.
- **Downstream adjusts, always.** When a lower package improves, every package above is rewritten to use it, breaking its own API where that is needed. A lower package is never bent, delayed or kept compatible for a consumer.
- **A top-level name is a claim.** A top-level type `X` says it is the universal X, and so owns `swift-x`. A type that is less than that nests under the domain it belongs to (`Motion.Scene`, not `Scene`).
- **Glue stays at the top.** An adapter over a platform framework (AppKit, AVFoundation) is a composition and holds no general logic; whatever in it is general moves down.
- A same-layer edge must be an essential semantic prerequisite and push no higher-layer policy down.

The test for any piece of code: what is this, stripped of the name its current home gave it? The answer picks the layer, the layer picks the repository, and everything above is rewritten to use it.

## A repository

- **Prose:** `README.md` is a repository's only prose, written as the guide an agent reads before using the code. It says what the code alone does not, and repeats nothing `Package.swift`, `metadata.yaml` or `LICENSE.md` already says. Besides it: `LICENSE.md`, an organization's community-health files in its `.github` repository, DocC catalogs, and test fixtures.
- **`.gitignore`:** generated by `institute` from a canon per repository class. It is a whitelist: `/*` ignores everything at the root, then `!/Sources`, `!/Tests`, `!/Package.swift` and the few other tracked entries come back, and inside `Sources` only Swift files and DocC catalogs do. Generated and tool state such as `Package.resolved` and `.build`, and stray Markdown, is never tracked because nothing un-ignores it. The cost is silence: a new kind of work is untracked and `git status` does not show it. Add that kind to the canon; never force-add it.

## CI and evidence

Each package repository carries one generated `ci.yml` that calls the reusable `swift-ci.yml` in [swift-institute/.github](https://github.com/swift-institute/.github). That workflow runs only the `institute` command: `ci -- package validate|plan|aggregate`, and `ci -- source` for Institute lint in the `Quality · source` job. `institute install` puts the same pinned binary on a Mac.

Evidence of record is a `workflow_dispatch` run of that CI, which always plans the full tier. A local green, a filtered run or a local `institute ci -- source` is iteration evidence. `gh run rerun` replays the old snapshot; dispatch a fresh run.

## State

GitHub is the only state outside the code: issues, labelled `decision` or `lint-candidate` where they fit, and the project Institute Work (private). No memory files, handover notes or local ledgers. A rule that ought to be checked and is not becomes a `lint-candidate` issue in [swift-institute/Issues](https://github.com/swift-institute/Issues), never prose here. Toolchain bugs use that repository's Toolchain bug form. Security reports follow the [security policy](https://github.com/swift-institute/.github/blob/main/SECURITY.md).

## Local builds

- Standalone package work: SwiftPM in the package directory (`swift build`, `swift test`).
- App work, or a package change proven through an app: that app's `.xcworkspace` through Xcode's own tools, with local package checkouts referenced by the workspace.

## Status

Public alpha. Packages land repository by repository, and APIs may change until first tagged releases. Swift Institute is an independent open-source project, not affiliated with Apple or the Swift open-source project. Maintained by [Coen ten Thije Boonkkamp](https://github.com/coenttb); contributions are welcome as pull requests on the relevant repository.

## License

Packages in the four layers use the Apache License 2.0; each repository's `LICENSE.md` is the authority for that repository.
