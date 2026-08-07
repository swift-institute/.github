import Foundation
import Repository_Policy
import Testing

/// `Parse` is defined as `Render`'s inverse, so the test is the identity
/// that definition asserts — over the seven real callers, not over
/// synthetic text a wrong parser and a wrong expectation could agree on.
///
/// The fixtures are read from `.github/scripts/tests/fixtures/callers/`
/// in place. They are corpus **data**: byte-for-byte snapshots of live
/// `ci.yml` files, and copying them into this package's `Fixtures`
/// directory would make a second spelling that drifts.
@Suite
struct RepositoryPolicyCallerParseTests {
    /// The seven real callers, with the repository each was fetched from.
    /// Provenance is `fixtures/callers/README.md`.
    static let callers: [(fixture: String, repository: String, layer: Repository.Policy.Caller.Layer)] = [
        ("array-primitives", "swift-primitives/swift-array-primitives", .primitives),
        ("copy-on-write", "swift-foundations/swift-copy-on-write", .institute),
        ("domain-standard", "swift-standards/swift-domain-standard", .standards),
        ("iso-9945", "swift-iso/swift-iso-9945", .standards),
        ("linux-standard", "swift-linux-foundation/swift-linux-standard", .standards),
        ("rfc-3986", "swift-ietf/swift-rfc-3986", .standards),
        ("windows-32", "swift-microsoft/swift-windows-32", .standards),
    ]

    static func text(_ fixture: String) throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()  // Repository Policy Tests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository-policy
            .deletingLastPathComponent()  // Tools
            .deletingLastPathComponent()  // the repository root
            .appending(path: ".github/scripts/tests/fixtures/callers/\(fixture).yml")
        return try String(contentsOf: root, encoding: .utf8)
    }

    /// The round-trip the port plan names: parse each real caller, render
    /// the recovered spec, parse that back, and require the two specs
    /// equal. `Parse(Render(spec)) == spec`, with `spec` supplied by the
    /// corpus rather than by this file.
    @Test(arguments: callers)
    func roundTripsEveryRealCallerThroughTheCurrentForm(
        caller: (fixture: String, repository: String, layer: Repository.Policy.Caller.Layer)
    ) throws {
        let spec = try Repository.Policy.Caller.Parse.caller(
            Self.text(caller.fixture), repository: caller.repository)
        #expect(spec.repository == caller.repository)
        #expect(spec.layer == caller.layer)

        let rendered = Repository.Policy.Caller.Render.current(spec)
        let recovered = try Repository.Policy.Caller.Parse.caller(
            rendered, repository: caller.repository)
        #expect(recovered == spec)
    }

    /// The same identity through the terminal form. `Render.direct` is a
    /// different projection of the same spec — different trigger set,
    /// different callee, the layer carried as a lint bundle instead of a
    /// wrapper org — so a spec that survives both round-trips is recovered
    /// from the *spec*, not from one form's incidental text.
    @Test(arguments: callers)
    func roundTripsEveryRealCallerThroughTheDirectForm(
        caller: (fixture: String, repository: String, layer: Repository.Policy.Caller.Layer)
    ) throws {
        let spec = try Repository.Policy.Caller.Parse.caller(
            Self.text(caller.fixture), repository: caller.repository)
        let recovered = try Repository.Policy.Caller.Parse.caller(
            Repository.Policy.Caller.Render.direct(spec), repository: caller.repository)
        #expect(recovered == spec)
    }

    /// Rendering is idempotent under parsing: the text fixpoint, which is
    /// the property a regeneration sweep actually depends on. Spec
    /// equality alone would still permit a renderer that emitted
    /// different bytes on the second pass.
    @Test(arguments: callers)
    func renderingIsAFixpointUnderParsing(
        caller: (fixture: String, repository: String, layer: Repository.Policy.Caller.Layer)
    ) throws {
        let spec = try Repository.Policy.Caller.Parse.caller(
            Self.text(caller.fixture), repository: caller.repository)
        let once = Repository.Policy.Caller.Render.current(spec)
        let twice = Repository.Policy.Caller.Render.current(
            try Repository.Policy.Caller.Parse.caller(once, repository: caller.repository))
        #expect(once == twice)
    }

    /// The legacy `docs:` job's overrides are recovered, not dropped.
    /// Three of the seven carry a real `platform-support`; this asserts
    /// the docs-side mapping with a caller built for it, since no fixture
    /// exercises a `docs:` `with:` block.
    @Test
    func recoversLegacyDocsOverridesOntoTerminalInputs() throws {
        let text = """
            name: CI

            on:
              push:
                branches:
                  - main

            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                with:
                  platform-support: apple,linux
                secrets: inherit

              docs:
                uses: swift-standards/.github/.github/workflows/swift-docs.yml@main
                with:
                  umbrella-module: Demo
                  exclude-modules: Internal
                secrets: inherit
            """
        let spec = try Repository.Policy.Caller.Parse.caller(
            text, repository: "swift-standards/swift-demo-standard")
        #expect(spec.inputs.map(\.key) == [
            "platform-support", "docs-umbrella-module", "docs-exclude-modules",
        ])
        #expect(spec.inputs.first { $0.key == "docs-umbrella-module" }?.value == "Demo")
    }

    /// Comments and blank lines differ freely; every real caller carries
    /// them, and `iso-9945` carries a seven-line comment *inside* its
    /// `with:` block.
    @Test
    func ignoresCommentsInsideBlocks() throws {
        let spec = try Repository.Policy.Caller.Parse.caller(
            Self.text("iso-9945"), repository: "swift-iso/swift-iso-9945")
        #expect(spec.inputs.count == 1)
        #expect(spec.inputs[0] == (key: "platform-support", value: "apple,linux"))
    }

    // MARK: - Failing closed
    //
    // Every refusal `parse_existing_caller` named, asserted as a refusal.
    // A parser that silently accepted these would let a regeneration
    // sweep erase a real customization, which is the failure mode the
    // typed error exists to prevent.

    @Test
    func refusesInlineSteps() throws {
        let text = """
            jobs:
              ci:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        #expect(throws: Repository.Policy.Caller.Error.unknownCustomization(
            "`ci` job carries inline steps/runs-on, not a thin caller")) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    @Test
    func refusesAnUnapprovedInput() throws {
        let text = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                with:
                  bespoke-knob: yes
            """
        #expect(throws: Repository.Policy.Caller.Error.unknownCustomization(
            "unapproved with: key bespoke-knob")) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    @Test
    func refusesAnUnexpectedJob() throws {
        let text = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                secrets: inherit

              publish:
                uses: swift-standards/.github/.github/workflows/swift-publish.yml@main
            """
        #expect(throws: Repository.Policy.Caller.Error.self) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    @Test
    func refusesACrossWrapperDocsRoute() throws {
        let text = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                secrets: inherit

              docs:
                uses: swift-primitives/.github/.github/workflows/swift-docs.yml@main
                secrets: inherit
            """
        #expect(throws: Repository.Policy.Caller.Error.self) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    @Test
    func refusesAnUnknownWrapperOrganization() throws {
        let text = """
            jobs:
              ci:
                uses: some-other-org/.github/.github/workflows/swift-ci.yml@main
                secrets: inherit
            """
        #expect(throws: Repository.Policy.Caller.Error.self) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    /// A tag pin is not a customization this type may normalise away —
    /// the whole caller must fail the canonical-shape check rather than
    /// be silently regenerated at `@main`.
    @Test
    func refusesANonMainPin() throws {
        let text = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@v1
                secrets: inherit
            """
        #expect(throws: Repository.Policy.Caller.Error.self) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    /// `integrated-docs` is generator-owned. TX10 deleted it, so `true`
    /// is tolerated on an existing caller and anything else refuses.
    @Test
    func refusesANonTrueIntegratedDocs() throws {
        let text = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                with:
                  integrated-docs: false
                secrets: inherit
            """
        #expect(throws: Repository.Policy.Caller.Error.unknownCustomization(
            "integrated-docs is present but not true")) {
            try Repository.Policy.Caller.Parse.caller(text, repository: "swift-iso/swift-x")
        }
    }

    /// The layer is recovered from the workflow the caller actually
    /// calls, never from the repository's organization — the same
    /// discipline `Caller.sameOrganization` follows. A cross-org caller
    /// is the case that separates the two.
    @Test
    func recoversTheLayerFromTheCalleeNotTheOwnerOrganization() throws {
        let layer = try Repository.Policy.Caller.Parse.layer(of: Self.text("windows-32"))
        #expect(layer == .standards)
        #expect(layer.wrapperOrganization != "swift-microsoft")
    }
}
