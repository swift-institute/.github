import CI_Contract

extension CI.SymbolGraph {
    /// One module's symbol graph.
    public struct Graph: Sendable, Equatable {
        /// The graph's file name, e.g. `Property_Primitives.symbols.json`
        /// or `Property_Primitives@Byte_Primitives.symbols.json`.
        public let name: String
        public private(set) var document: JSON

        public init(name: String, document: JSON) {
            self.name = name
            self.document = document
        }

        public init(name: String, text: String) throws(JSON.Error) {
            self.init(name: name, document: try JSON(text: text))
        }

        /// The module a graph file belongs to. An `@` suffix marks an
        /// extension graph — symbols the named module adds to another —
        /// and belongs to the module before the `@`.
        public static func module(ofFile name: String) -> String {
            let stem = name.split(separator: "@", maxSplits: 1).first.map(String.init) ?? name
            guard stem.hasSuffix(".symbols.json") else { return stem }
            return String(stem.dropLast(".symbols.json".count))
        }

        public var module: String { Self.module(ofFile: name) }

        /// USR → doc comment, for every symbol that documents one.
        public var documentedSymbols: [String: JSON] {
            var documented: [String: JSON] = [:]
            for symbol in document["symbols"]?.array ?? [] {
                guard let comment = symbol["docComment"],
                      let lines = comment["lines"]?.array, !lines.isEmpty,
                      let usr = symbol["identifier"]?["precise"]?.string
                else { continue }
                if documented[usr] == nil { documented[usr] = comment }
            }
            return documented
        }

        /// Inject doc comments from sibling graphs into symbols that
        /// carry none, and report how many were injected.
        ///
        /// Against a current toolchain this patches nothing: the emitter
        /// already carries `@_exported` re-export doc comments into the
        /// umbrella's graph. It is kept as a defensive no-op, and the
        /// count is what says which of those two worlds we are in — a
        /// nonzero count in the docs job is a toolchain regression
        /// having been caught, not a step doing its job.
        public mutating func patch(from documented: [String: JSON]) -> Int {
            guard let symbols = document["symbols"]?.array else { return 0 }
            var patched = 0
            var updated: [JSON] = []
            updated.reserveCapacity(symbols.count)
            for symbol in symbols {
                var symbol = symbol
                let hasComment = !(symbol["docComment"]?["lines"]?.array ?? []).isEmpty
                if !hasComment,
                   let usr = symbol["identifier"]?["precise"]?.string,
                   let replacement = documented[usr] {
                    symbol.set("docComment", to: replacement)
                    patched += 1
                }
                updated.append(symbol)
            }
            document.set("symbols", to: .array(updated))
            return patched
        }
    }
}
