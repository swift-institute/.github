import CI_Contract

extension CI.SymbolGraph {
    /// The umbrella-graph isolation step.
    ///
    /// Isolation is the load-bearing half of this step, and the reason
    /// it exists at all: handing DocC the whole graph pool makes the
    /// same USR appear under both its declaring module and the umbrella,
    /// which is an ambiguity DocC resolves by breaking every in-catalog
    /// `` `Symbol` `` span. So the output directory holds the umbrella's
    /// graphs and nothing else.
    public struct Umbrella: Sendable, Equatable {
        /// The umbrella module's name in underscore form, e.g.
        /// `Property_Primitives`.
        public let module: String
        /// Modules whose doc comments are not donors — a test-support
        /// module, typically.
        public let excludedModules: Set<String>

        public init(module: String, excludedModules: Set<String> = []) {
            self.module = module
            self.excludedModules = excludedModules
        }

        public enum Error: Swift.Error, Equatable {
            case emptyGraphDirectory
            case noGraphForUmbrella(String)
            case unreadable(String)
        }

        /// Whether a graph file belongs to the umbrella: its own graph,
        /// or one of its extension graphs.
        public func owns(file name: String) -> Bool {
            name == "\(module).symbols.json" || name.hasPrefix("\(module)@")
        }

        /// The graph file names in a directory, in the order the step
        /// reads them.
        public static func graphFiles(in names: [String]) -> [String] {
            names.filter { $0.hasSuffix(".symbols.json") }.sorted()
        }

        /// What the step produces: the umbrella's patched graphs, and
        /// the number of symbols patched across them.
        public struct Isolation: Sendable, Equatable {
            public let graphs: [Graph]
            public let patchedSymbols: Int

            public init(graphs: [Graph], patchedSymbols: Int) {
                self.graphs = graphs
                self.patchedSymbols = patchedSymbols
            }

            /// The line `swift-docs.yml` reads to know the step ran.
            public func summary(outputDirectory: String) -> String {
                "patched \(patchedSymbols) symbol(s) across \(graphs.count) "
                    + "umbrella graph file(s); wrote to \(outputDirectory)"
            }
        }

        /// Patch and isolate.
        ///
        /// An empty pool and a pool with no umbrella graph both refuse.
        /// The second is the one that matters: DocC given an empty
        /// additional-graph directory succeeds and documents nothing, so
        /// a missing umbrella graph has to fail here or it does not fail
        /// anywhere.
        public func isolate(from pool: [Graph]) throws(Error) -> Isolation {
            if pool.isEmpty { throw .emptyGraphDirectory }
            let umbrellaGraphs = pool.filter { owns(file: $0.name) }
            if umbrellaGraphs.isEmpty { throw .noGraphForUmbrella(module) }

            var documented: [String: JSON] = [:]
            for graph in pool where graph.module != module
                && !excludedModules.contains(graph.module) {
                for (usr, comment) in graph.documentedSymbols where documented[usr] == nil {
                    documented[usr] = comment
                }
            }

            var patched: [Graph] = []
            var total = 0
            for graph in umbrellaGraphs {
                var graph = graph
                total += graph.patch(from: documented)
                patched.append(graph)
            }
            return Isolation(graphs: patched, patchedSymbols: total)
        }

        /// Patch and isolate a file-backed graph pool without retaining it whole.
        ///
        /// Umbrella graphs are loaded first. Donor graphs are then loaded one at a
        /// time, and only while an umbrella symbol still lacks documentation. This
        /// bounds the retained input to the output graphs and the comments they need.
        public func isolate(
            files names: [String], loading graph: (String) -> Graph?
        ) throws(Error) -> Isolation {
            let names = Self.graphFiles(in: names)
            if names.isEmpty { throw .emptyGraphDirectory }

            let owned = names.filter { owns(file: $0) }
            if owned.isEmpty { throw .noGraphForUmbrella(module) }

            var umbrellaGraphs: [Graph] = []
            umbrellaGraphs.reserveCapacity(owned.count)
            for name in owned {
                guard let graph = graph(name) else { throw .unreadable(name) }
                umbrellaGraphs.append(graph)
            }

            var needed: Set<String> = []
            for graph in umbrellaGraphs {
                needed.formUnion(graph.undocumented)
            }
            if needed.isEmpty {
                return Isolation(graphs: umbrellaGraphs, patchedSymbols: 0)
            }

            var documented: [String: JSON] = [:]
            for name in names where !owns(file: name)
                && !excludedModules.contains(Graph.module(ofFile: name))
                && !needed.isEmpty {
                guard let donor = graph(name) else { throw .unreadable(name) }
                for (identifier, comment) in donor.documented(matching: needed) {
                    documented[identifier] = comment
                    needed.remove(identifier)
                }
            }

            var patched: [Graph] = []
            patched.reserveCapacity(umbrellaGraphs.count)
            var total = 0
            for graph in umbrellaGraphs {
                var graph = graph
                total += graph.patch(from: documented)
                patched.append(graph)
            }
            return Isolation(graphs: patched, patchedSymbols: total)
        }
    }
}
