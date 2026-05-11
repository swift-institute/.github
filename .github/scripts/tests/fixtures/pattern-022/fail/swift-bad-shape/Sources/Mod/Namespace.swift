// `~Copyable` parent declared with nested types in its body — VIOLATION of
// [PATTERN-022]. Nested types MUST be hoisted into separate files via
// `extension Namespace where Element: ~Copyable { ... }`.
public enum Namespace<Element: ~Copyable> {
    public struct NestedData {
        public init() {}
    }

    public enum NestedKind {
        case a
        case b
    }
}
