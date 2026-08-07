import CI_Contract
import CI_Workflow

extension CI.Inventory {
    /// The whole verdict inventory, and its canonical JSON.
    public struct Document: Sendable, Equatable {
        /// Schema 2 is the terminal one-hop topology.
        ///
        /// Schema 1 carried a `wrappers` member — one entry per layer
        /// wrapper repository, with an outer `ci-ok` and the layer's
        /// required jobs sitting outside the universal verdict. There
        /// are no layer wrappers. The member is not renamed or emptied;
        /// it is gone, and the version says so.
        public static let schemaVersion = 2

        /// Hops from a consumer's caller workflow to the verdict:
        /// `ci` → `matrix` → the universal's `ci-ok`. One.
        public static let callerHops = 1

        public let universal: Universal

        public init(universal: Universal) {
            self.universal = universal
        }

        /// Derives the inventory from the universal workflow's text.
        public init(universalWorkflow text: String) throws(Error) {
            let document: CI.Workflow.Document
            do throws(CI.Workflow.YAML.Error) {
                document = try CI.Workflow.Document(name: "swift-ci.yml", text: text)
            } catch {
                throw .unreadableWorkflow(message: error.message)
            }
            self.universal = try Universal(document)
        }

        public var node: CI.Workflow.YAML.Node {
            .mapping(
                .init([
                    (.text("schema_version"), .integer(Self.schemaVersion)),
                    (.text("generated_by"), .text("institute-ci verdict-inventory")),
                    (.text("caller_hops"), .integer(Self.callerHops)),
                    (.text("universal"), universal.node),
                ]))
        }

        /// The document as canonical JSON — key-sorted, one deterministic
        /// spelling per value — through the reader's own serializer, so
        /// the inventory never grows a second one.
        public var canonicalJSON: String { CI.Workflow.YAML.Canonical.json(node) }
    }
}
