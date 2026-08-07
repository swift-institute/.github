import CI_Contract
import Testing

@testable import CI_Workflow

@Suite
struct CIWorkflowYAMLTests {
    typealias YAML = CI.Workflow.YAML

    @Suite
    struct Unit {
        typealias YAML = CI.Workflow.YAML

        @Test(
            arguments: [
                ("yes", true), ("Yes", true), ("YES", true), ("on", true), ("ON", true),
                ("true", true), ("TRUE", true),
                ("no", false), ("off", false), ("Off", false), ("false", false),
            ])
        func `boolean spellings`(text: String, expected: Bool) {
            #expect(YAML.Resolver.resolve(text) == .boolean(expected))
        }

        @Test func `numbers and null resolve`() {
            #expect(YAML.Resolver.resolve("45") == .integer(45))
            #expect(YAML.Resolver.resolve("1_000") == .integer(1000))
            #expect(YAML.Resolver.resolve("0x1f") == .integer(31))
            #expect(YAML.Resolver.resolve("~") == .null)
            #expect(YAML.Resolver.resolve("null") == .null)
        }

        @Test func `references and versions stay text`() {
            #expect(YAML.Resolver.resolve("org/repo@main") == .text("org/repo@main"))
            #expect(YAML.Resolver.resolve("v4") == .text("v4"))
            #expect(YAML.Resolver.resolve("ubuntu-latest") == .text("ubuntu-latest"))
        }

        @Test func `mapping order is preserved`() throws {
            // Findings are emitted in document order, so the reader must
            // not reorder a mapping.
            let node = try YAML.Parser.parse("jobs:\n  zebra:\n    id: 1\n  alpha:\n    id: 2\n")
            #expect(try #require(node["jobs"]?.mapping).textKeys == ["zebra", "alpha"])
        }

        @Test func `flow collections`() throws {
            let node = try YAML.Parser.parse(
                "branches: [main, 'release/*']\nwith: {fetch-depth: 0}\n")
            #expect(node["branches"] == .sequence([.text("main"), .text("release/*")]))
            #expect(node["with"]?["fetch-depth"] == .integer(0))
        }

        @Test func `sequence of mappings with indented continuations`() throws {
            let node = try YAML.Parser.parse(
                """
                steps:
                  - uses: actions/checkout@v6
                  - name: Build
                    run: swift build
                    continue-on-error: true
                """)
            let steps = try #require(node["steps"]?.sequence)
            #expect(steps.count == 2)
            #expect(steps[0]["uses"] == .text("actions/checkout@v6"))
            #expect(steps[1]["run"] == .text("swift build"))
            #expect(steps[1]["continue-on-error"] == .boolean(true))
        }

        @Test func `literal block scalar keeps breaks and hashes`() throws {
            let node = try YAML.Parser.parse(
                """
                run: |
                  echo one
                  # not a comment here
                name: after
                """)
            #expect(node["run"] == .text("echo one\n# not a comment here\n"))
            #expect(node["name"] == .text("after"))
        }

        @Test func `stripped block scalar drops the trailing newline`() throws {
            #expect(try YAML.Parser.parse("run: |-\n  echo one\n")["run"] == .text("echo one"))
        }
    }

    @Suite
    struct `Edge Case` {
        typealias YAML = CI.Workflow.YAML

        @Test func `on is a boolean key under yaml 1.1`() throws {
            // The quirk the whole reader exists to preserve: PyYAML
            // resolves the key `on` to `true`, so a string lookup misses
            // and callers must recover through the boolean.
            let body = try #require(
                YAML.Parser.parse("on:\n  push:\n    branches: [main]\n").mapping)
            #expect(body["on"] == nil)
            #expect(body[node: .boolean(true)] != nil)
        }

        @Test func `quoting suppresses resolution`() throws {
            #expect(try #require(YAML.Parser.parse("\"on\":\n  push:\n").mapping)["on"] != nil)
        }

        @Test(arguments: ["yEs", "oN", "y", "n", "maybe", "on-push", ""])
        func `spellings that stay text`(text: String) {
            #expect(YAML.Resolver.resolve(text).boolean == nil)
        }

        @Test func `comments are not content but hashes in values are`() throws {
            let node = try YAML.Parser.parse(
                """
                # leading comment
                name: CI   # trailing comment
                colour: '#ffffff'
                """)
            #expect(node["name"] == .text("CI"))
            #expect(node["colour"] == .text("#ffffff"))
        }

        @Test func `anchored values are read not refused`() throws {
            // PyYAML accepts these, so refusing them would make the
            // reader stricter than what it replaces.
            let jobs = try #require(
                YAML.Parser.parse(
                    """
                    jobs:
                      build: &inline
                        runs-on: ubuntu-latest
                      mirror: *inline
                    """)["jobs"]?.mapping)
            #expect(jobs["build"] == jobs["mirror"])
            #expect(jobs["mirror"]?["runs-on"] == .text("ubuntu-latest"))
        }

        @Test func `uncovered constructs are refused not guessed at`() {
            #expect(throws: YAML.Error.self) {
                _ = try YAML.Parser.parse("runs-on: [ubuntu-latest\nsteps:\n")
            }
            #expect(throws: YAML.Error.self) {
                _ = try YAML.Parser.parse("value: *missing\n")
            }
        }

        @Test func `empty document is null`() throws {
            #expect(try YAML.Parser.parse("") == .null)
            #expect(try YAML.Parser.parse("# only a comment\n") == .null)
        }
    }

    @Suite
    struct Integration {
        typealias YAML = CI.Workflow.YAML

        @Test func `canonical rendering of a realistic caller is stable`() throws {
            let node = try YAML.Parser.parse(
                """
                name: CI

                on:
                  push:
                    branches: [main]

                jobs:
                  ci:
                    uses: swift-primitives/.github/.github/workflows/swift-ci.yml@main
                    secrets: inherit
                """)
            // Key-sorted, so `true` (the resolved `on` key) sorts last.
            #expect(
                YAML.Canonical.json(node) == """
                    {"jobs":{"ci":{"secrets":"inherit",\
                    "uses":"swift-primitives/.github/.github/workflows/swift-ci.yml@main"}},\
                    "name":"CI","true":{"push":{"branches":["main"]}}}
                    """)
        }
    }
}
