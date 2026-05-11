// Nested type lives in its own file via `extension Parent where Element: ~Copyable`
// per [PATTERN-022]. The parent file (`Namespace.swift`) has an empty body.
extension Namespace where Element: ~Copyable {
    public enum NestedData {}
}
