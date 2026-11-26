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

Layer 3 is an organization of organizations. Each authority has its own: [swift-ietf](https://github.com/swift-ietf) (`swift-rfc-{number}`), [swift-iso](https://github.com/swift-iso) (`swift-iso-{number}`), [swift-ieee](https://github.com/swift-ieee), [swift-iec](https://github.com/swift-iec), [swift-w3c](https://github.com/swift-w3c), [swift-whatwg](https://github.com/swift-whatwg), [swift-ecma](https://github.com/swift-ecma), [swift-incits](https://github.com/swift-incits), [swift-bipm](https://github.com/swift-bipm), [swift-linux-foundation](https://github.com/swift-linux-foundation), and the vendors [swift-arm-ltd](https://github.com/swift-arm-ltd), [swift-intel](https://github.com/swift-intel), [swift-riscv](https://github.com/swift-riscv) and [swift-microsoft](https://github.com/swift-microsoft). swift-standards itself holds the policy-free convergence packages, `swift-{concept}-standard`, which absorb spec revisions so consumers never change. It also holds the packages of an authority that has only a few (SMPTE, ITU, NIST); an authority gets its own organization once it has several. One spec can carry two designations (IEEE 1003.1 is ISO/IEC 9945); such packages split the spec by surface and are not duplicates. Local checkouts nest the same way, with the authority folders inside the swift-standards folder.

Older text says Primitives for layers 1 and 2 and Foundations for layer 4; neither organization exists.

## Placement and direction

Can you point to an external spec, man page or SDK document that defines this surface? Yes: layer 3. No: layer 1 if it is an atomic prerequisite, layer 2 if it is built from atoms alone, layer 4 otherwise. An extraction without a clear answer goes to swift-compositions.

Dependencies point down: atoms on atoms; molecules on atoms and molecules; standards on atoms, molecules and standards; compositions on anything; products, which live outside the Institute, on all of it. The lower a package sits, the more it is perfected on its own terms, and everything above it bends to fit. What the check cannot decide:

- **A package is finished to its own laws.** It is designed around the concept it names, never around what one consumer needs. No app, product or higher package shapes a lower one.
- **A general idea lives at the lowest layer its dependencies allow, now.** Layer follows essence, never the current edges or the current home. When part of a higher package is a general concept (an exact rate, a floor, a PSNR), it moves down in the same piece of work; waiting for a second consumer is deciding from downstream. When an edge points up, the capability moves down; the consumer never lifts. This is about where existing code lives, not about building what nothing uses yet.
- **A gap is fixed where it is.** Every capability has one owner; everything else composes it. A helper in a higher package that makes up for something missing below is a defect in the lower package: file it there, fix it there, then delete the helper.
- **Downstream adjusts, always.** When a lower package improves, every package above is rewritten to use it, breaking its own API where that is needed. A lower package is never bent, delayed or kept compatible for a consumer.
- **A top-level name is a claim.** A top-level type `X` says it is the universal X, and so owns `swift-x`. A type that is less than that nests under the domain it belongs to (`Motion.Scene`, not `Scene`). A kind of quantity is a root when its plain name means that one quantity everywhere (`Mass`, `Pressure`, `Stress`). A kind whose name needs a qualifier nests under its family (`Modulus.Young`, `Moment.Inertia`), and a root whose bare name is first read as something other than the quantity (a person's name, as in Poisson's ratio) is renamed or nested.
- **Type phrasing follows domain size, uniformity and ownership.**
  - Package ownership matches the dotted path 1:1: `swift-x` owns `X`, a package `swift-x-y` owns `X.Y` (depending down on `swift-x`), and `swift-x-y-z` owns `X.Y.Z` (depending down on `swift-x-y`). I1 says which `X.Y` has a package and which stays in a target of `swift-x`. A package name means nothing else: `swift-x-y` is never glue between `swift-x` and `swift-y` (I9).
  - `X.Y` nests only when `X` is strictly the larger domain (`Y` *is a* `X`, or *is a direct part of* `X`) and `Y` has its own representation, invariants or operations (`Buffer.Linear`, `Async.Semaphore`, `Color.Oklab`). A peer medium or orchestrator that merely produces or uses `X` owns its own root (`Watercolor`, `Story`), never `X.Y`.
  - `X<Y>` parameterises when one uniform representation and algorithm works across an open or polymorphic family of `Y`s (`Vector<N, Scalar>`, `Interval<Bound>`, `Coordinate<Space>`).
  - `X<Context>.Z` curries ambient parameters on an uninhabited namespace `enum` only when every nested type and `typealias` depends on `Context` (`Geometry<Scalar, Space>.Size<2>`, `Optic<Whole, Part>.Isomorphism`). Where any sibling is independent of `Context`, `X` stays a non-generic `enum` root (`Story.Script<Scene, Theme>` beside `Story.Stage`). A generic value struct may still nest `Self.Error` (`Matrix<Rows, Columns, Scalar>.Error`).
  - A concept defined by a published standard lives canonically under its authority's dotted namespace, 1:1 with the authoritative specification document (`W3C.Compositing`, `W3C.CSS`, `W3C.PNG`, `WHATWG.HTML`, ``ISO.`9945` ``, ``IETF.RFC.`1035` ``, ``IEC.`61966` ``); higher domains use it directly rather than wrapping a duplicate.
  - A higher-layer capability inverts ownership at the end of the noun chain (`Radix.Formatter`, `Byte.Size.Formatter`, `Map.Coder`, `Predicate.Parser`, `X.View`) so dependencies still point down, with only capability-internal support types (`.Error`, `.Options`, `.Context`) beneath it.
  - Standalone `Y` and nested `X.Y` coexist only when semantically distinct, with `Y` the generic concept and `X.Y` the `X`-specific one (`Order` and `Bit.Order`, `Line` and `ASCII.Line`, `Vector` and `CPU.Vector`).
- **Glue stays at the top.** An adapter over a platform framework (AppKit, AVFoundation) is a composition and holds no general logic; whatever in it is general moves down.
- A same-layer edge must be an essential semantic prerequisite and push no higher-layer policy down. Glue behind a trait (I9) is the one optional same-layer edge.

The test for any piece of code: what is this, stripped of the name its current home gave it? The answer picks the layer, the layer picks the repository, and everything above is rewritten to use it.

**Pre-Institute.** A package meant for a layer but not ready for it (experimental, still in development, or private for a reason) lives in its author's organization until it moves. It follows every rule here and runs the same checks, locally while it is private. Its README's first lines name the organization it is going to and what blocks the move. No Institute package depends on a pre-Institute one: when one is needed, it moves first.

**Private before launch.** A repository in an Institute organization may be private until its vertical is ready to show. It follows every rule here; hosted CI skips it, so its check of record is a local run at the pushed head. A public package never depends on a private one.

## A package

What no check decides yet, by id; each lint candidate is an issue in [swift-institute/Issues](https://github.com/swift-institute/Issues).

- **I1, a package or a target.** A nested type `X.Y` that is a kind of `X` or a part of it, with its own representation, invariants or operations, is its own package `swift-x-y` (`Buffer.Linear`, `Acoustics.String`). A role of `X` is a target of `swift-x`: a capability over `X`'s own types (`Picture.Coder` in `Picture Coder`, `Sound.File` in `Sound File`), or one of `X`'s own types made for one backend (`Picture.Renderer` in `Picture Metal`), with a trait gating what only that role needs (I7). A role is its own package `swift-x-y` only when it needs a layer above `swift-x` (`Shader.Compiler`). Platform glue (I2) and glue to a peer (I9) are targets too. Anything else stays in the primary target. Never decided by waiting for a second consumer, and never by size.
- **I2, platform glue.** An adapter over a platform framework (AppKit, UIKit, SwiftUI, AVFoundation, ScreenCaptureKit) is its own target, named for the adapter and conditional on the platform. The primary target never imports one, and the adapter holds no general logic (Issues#287).
- **I3, Foundation.** No main target imports Foundation or uses its types. Foundation enters through a `… Foundation Integration` target. A glue target handed a Foundation type by a framework's own API keeps it at that edge and works in Institute types.
- **I4, products.** A package has one primary product named for it (swift-kernel gives `Kernel`), holding the concept the name claims. Every other product is that name plus a role in words (`Motion Encoding`) (Issues#288).
- **I5, Test Support.** `<Thing> Test Support` holds what other packages' tests need: builders, invented fixtures as values, and the package's laws as functions. It depends on its own targets and other Test Support products only, and only test targets depend on it. A helper copied into two packages' tests belongs in the Test Support of the package it exercises (Issues#289).
- **I6, kinds of target.** A package holds library targets and their tests, plus only these: a C target named `… Shims` with no logic; a dynamic library product where the mechanism needs one, with the reason among the README's laws; an executable target as a test fixture that no product vends. A tool people run is its own package (Issues#290).
- **I7, gating.** In a package with one main product a dependency is unconditional unless it is heavy (a database driver, NIO or an HTTP server, a C codec, an adapter over a platform framework): that sits behind a trait or in a target of its own. A light Institute dependency is never gated only to shorten a consumer's graph. In a package with several main products, a dependency that only a secondary product needs sits behind a trait, light or not; the `untraited partial dependency` check decides. No package declares default traits: each consumer names the traits it uses (the `default trait` check). While SwiftPM cannot resolve one package requested with two trait sets (Issues#123), a product dependency of a trait's target may be unconditional; the trait still gates that target's source.
- **I8, semantic types over speed.** A semantic type (`Vector<3, Scalar>`) is never flattened into raw scalars, arrays or tuples for speed. When a profile blames the type, the type itself is made faster, or the slowness is filed as a toolchain issue in [swift-institute/Issues](https://github.com/swift-institute/Issues), and tests are made faster by doing less work.
- **I9, glue between peers.** Code that makes one package's type work with another's (a conformance, a conversion, an extension) is a target in the package whose type gains it, named for both (`Story Watercolor`), behind a trait named for the other package. Where that edge would point up a layer, the target lives in the higher package. Two packages never hold glue to each other: where each type gains from the other, one package holds all of it. Glue is never a repository of its own (Issues#381).

## A repository

- **Prose:** prose is one `README.md` per package: the root's, and each nested package's. Besides it: `LICENSE.md`, an organization's community-health files in its `.github` repository, DocC catalogs, and test fixtures. A README is written as the guide an agent reads before using the code. It says what the code alone does not, and repeats nothing `Package.swift`, `metadata.yaml` or `LICENSE.md` already says.
- **`.gitignore`:** generated by `institute` from a canon per repository class. It is a whitelist: `/*` ignores everything at the root, then `!/Sources`, `!/Tests`, `!/Package.swift` and the few other tracked entries come back, and inside `Sources` only Swift files and DocC catalogs do. Generated and tool state such as `Package.resolved` and `.build`, and stray Markdown, is never tracked because nothing un-ignores it. The cost is silence: a new kind of work is untracked and `git status` does not show it. Add that kind to the canon; never force-add it.

## CI and evidence

Each package repository carries one generated `ci.yml` that calls the reusable `swift-ci.yml` in [swift-institute/.github](https://github.com/swift-institute/.github). That workflow runs only the `institute` command: `ci -- package validate|plan|aggregate`, and `ci -- source` for Institute lint in the `Quality · source` job. `institute install` puts the same pinned binary on a Mac.

Evidence of record is that CI's run at the pushed head of `main`, which plans the full tier; no second run is dispatched for it. A local green, a filtered run or a local `institute ci -- source` is iteration evidence. `gh run rerun` replays the old snapshot; where a fresh run is needed, dispatch one.

## State

GitHub is the only state outside the code: issues, labelled `decision` or `lint-candidate` where they fit, and the project Institute Work (private). No memory files, handover notes or local ledgers. A rule that ought to be checked and is not becomes a `lint-candidate` issue in [swift-institute/Issues](https://github.com/swift-institute/Issues), never prose here. Toolchain bugs use that repository's Toolchain bug form. Security reports follow the [security policy](https://github.com/swift-institute/.github/blob/main/SECURITY.md).

## Local builds

- Standalone package work: SwiftPM in the package directory (`swift build`, `swift test`).
- App work, or a package change proven through an app: that app's `.xcworkspace` through Xcode's own tools, with local package checkouts referenced by the workspace.

## Status

Public alpha. Packages land repository by repository, and APIs may change until first tagged releases. Swift Institute is an independent open-source project, not affiliated with Apple or the Swift open-source project. Maintained by [Coen ten Thije Boonkkamp](https://github.com/coenttb); contributions are welcome as pull requests on the relevant repository.

## License

Packages in the four layers use the Apache License 2.0; each repository's `LICENSE.md` is the authority for that repository.
