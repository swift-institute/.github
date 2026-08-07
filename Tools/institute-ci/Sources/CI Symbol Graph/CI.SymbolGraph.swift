import CI_Contract

// `CI.SymbolGraph` owns the umbrella-graph preparation step of the DocC
// pipeline ([DOC-019a]; Research `docc-multi-target-documentation-
// aggregation.md` R3), retired from `patch-umbrella-symbol-graph.py`.
//
// It sits in the public CI package rather than the credentialed one: it
// reads and writes files a build produced, holds no credential, and its
// only consumer is `swift-docs.yml`. The class it was dispatched under
// is a unit of work, not a claim about who owns it.
extension CI {
    /// Symbol-graph preparation for umbrella-module documentation.
    public enum SymbolGraph {}
}
