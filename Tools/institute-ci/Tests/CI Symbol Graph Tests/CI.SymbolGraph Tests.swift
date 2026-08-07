import CI_Contract
import Testing

@testable import CI_Symbol_Graph

/// The umbrella symbol-graph step, over recorded graphs.
@Suite
struct CISymbolGraphTests {
    static func graph(
        _ name: String, symbols: [(usr: String, documented: Bool)]
    ) -> CI.SymbolGraph.Graph {
        let encoded = symbols.map { symbol -> CI.SymbolGraph.JSON in
            var members: [String: CI.SymbolGraph.JSON] = [
                "identifier": .object(["precise": .string(symbol.usr)])
            ]
            if symbol.documented {
                members["docComment"] = .object([
                    "lines": .array([.object(["text": .string("doc for \(symbol.usr)")])])
                ])
            }
            return .object(members)
        }
        return CI.SymbolGraph.Graph(
            name: name, document: .object(["symbols": .array(encoded)]))
    }

    @Suite
    struct ModuleNaming {
        @Test func `a primary graph names its module`() {
            #expect(
                CI.SymbolGraph.Graph.module(ofFile: "Property_Primitives.symbols.json")
                    == "Property_Primitives")
        }

        @Test func `an extension graph belongs to the module before the at sign`() {
            #expect(
                CI.SymbolGraph.Graph.module(
                    ofFile: "Property_Primitives@Byte_Primitives.symbols.json")
                    == "Property_Primitives")
        }

        @Test func `only symbol graphs are in the pool, and the pool is ordered`() {
            #expect(
                CI.SymbolGraph.Umbrella.graphFiles(in: [
                    "B.symbols.json", "notes.md", "A.symbols.json", "A@B.symbols.json",
                ]) == ["A.symbols.json", "A@B.symbols.json", "B.symbols.json"])
        }

        @Test func `the umbrella owns its primary and its extension graphs only`() {
            let umbrella = CI.SymbolGraph.Umbrella(module: "Umbrella")
            #expect(umbrella.owns(file: "Umbrella.symbols.json"))
            #expect(umbrella.owns(file: "Umbrella@Donor.symbols.json"))
            #expect(!umbrella.owns(file: "Donor.symbols.json"))
            #expect(!umbrella.owns(file: "UmbrellaOther.symbols.json"))
        }
    }

    @Suite
    struct Isolation {
        static let pool = [
            CISymbolGraphTests.graph(
                "Donor.symbols.json", symbols: [("s:Donor1", true), ("s:Donor2", true)]),
            CISymbolGraphTests.graph(
                "Support.symbols.json", symbols: [("s:Support1", true)]),
            CISymbolGraphTests.graph(
                "Umbrella.symbols.json",
                symbols: [("s:Donor1", false), ("s:Own", true)]),
            CISymbolGraphTests.graph(
                "Umbrella@Donor.symbols.json", symbols: [("s:Donor2", false)]),
        ]

        @Test func `only the umbrella's graphs reach the output`() throws {
            let isolation = try CI.SymbolGraph.Umbrella(module: "Umbrella")
                .isolate(from: Self.pool)
            #expect(
                isolation.graphs.map(\.name)
                    == ["Umbrella.symbols.json", "Umbrella@Donor.symbols.json"])
        }

        @Test func `a missing doc comment is taken from the declaring module`() throws {
            let isolation = try CI.SymbolGraph.Umbrella(module: "Umbrella")
                .isolate(from: Self.pool)
            #expect(isolation.patchedSymbols == 2)
            let symbols = isolation.graphs[0].document["symbols"]?.array ?? []
            let patched = symbols.first { $0["identifier"]?["precise"]?.string == "s:Donor1" }
            #expect(
                patched?["docComment"]?["lines"]?.array?.first?["text"]?.string
                    == "doc for s:Donor1")
        }

        @Test func `an existing doc comment is never overwritten`() throws {
            let isolation = try CI.SymbolGraph.Umbrella(module: "Umbrella")
                .isolate(from: [
                    CISymbolGraphTests.graph("Donor.symbols.json", symbols: [("s:Own", true)]),
                    CISymbolGraphTests.graph("Umbrella.symbols.json", symbols: [("s:Own", true)]),
                ])
            #expect(isolation.patchedSymbols == 0)
            let symbols = isolation.graphs[0].document["symbols"]?.array ?? []
            #expect(
                symbols.first?["docComment"]?["lines"]?.array?.first?["text"]?.string
                    == "doc for s:Own")
        }

        @Test func `an excluded module donates nothing`() throws {
            let isolation = try CI.SymbolGraph.Umbrella(
                module: "Umbrella", excludedModules: ["Donor"])
                .isolate(from: Self.pool)
            // Only the extension graph's symbol is left unpatched too:
            // both its donors were excluded.
            #expect(isolation.patchedSymbols == 0)
        }

        @Test func `the current toolchain's already-complete graph patches nothing`() throws {
            // The emitter carries `@_exported` re-export doc comments
            // natively, so a zero here is the expected world and a
            // nonzero one is a toolchain regression having been caught.
            let isolation = try CI.SymbolGraph.Umbrella(module: "Umbrella")
                .isolate(from: [
                    CISymbolGraphTests.graph("Donor.symbols.json", symbols: [("s:A", true)]),
                    CISymbolGraphTests.graph("Umbrella.symbols.json", symbols: [("s:A", true)]),
                ])
            #expect(isolation.patchedSymbols == 0)
            #expect(
                isolation.summary(outputDirectory: "/tmp/out")
                    == "patched 0 symbol(s) across 1 umbrella graph file(s); wrote to /tmp/out")
        }

        @Test func `an empty graph directory refuses`() {
            #expect(throws: CI.SymbolGraph.Umbrella.Error.emptyGraphDirectory) {
                try CI.SymbolGraph.Umbrella(module: "Umbrella").isolate(from: [])
            }
        }

        @Test func `a pool with no umbrella graph refuses`() {
            // DocC given an empty additional-graph directory succeeds
            // and documents nothing, so this has to fail here or it
            // fails nowhere.
            #expect(throws: CI.SymbolGraph.Umbrella.Error.noGraphForUmbrella("Umbrella")) {
                try CI.SymbolGraph.Umbrella(module: "Umbrella")
                    .isolate(from: [
                        CISymbolGraphTests.graph("Donor.symbols.json", symbols: [])
                    ])
            }
        }
    }

    @Suite
    struct DocumentPreservation {
        @Test func `members the step knows nothing about survive the round trip`() throws {
            let text = """
            {"metadata":{"formatVersion":{"major":0,"minor":6,"patch":0}},\
            "module":{"name":"Umbrella","platform":{"architecture":"arm64"}},\
            "symbols":[],"relationships":[{"kind":"memberOf","source":"s:A","target":"s:B"}]}
            """
            var graph = try CI.SymbolGraph.Graph(name: "Umbrella.symbols.json", text: text)
            #expect(graph.patch(from: [:]) == 0)
            let rendered = try graph.document.text()
            let reread = try CI.SymbolGraph.JSON(text: rendered)
            #expect(reread["metadata"]?["formatVersion"]?["minor"] == .number(6))
            #expect(reread["module"]?["platform"]?["architecture"] == .string("arm64"))
            #expect(reread["relationships"]?.array?.count == 1)
        }

        @Test func `a graph that is not JSON refuses`() {
            #expect(throws: CI.SymbolGraph.JSON.Error.malformed("not JSON")) {
                try CI.SymbolGraph.Graph(name: "Umbrella.symbols.json", text: "{")
            }
        }
    }
}
