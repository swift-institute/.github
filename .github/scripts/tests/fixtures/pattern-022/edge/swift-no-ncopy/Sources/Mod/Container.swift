// Container is Copyable-generic (no `~Copyable` constraint); nested types
// inside its body are NOT in scope for [PATTERN-022]. Edge fixture asserts
// the validator does not flag this case.
public enum Container<Element> {
    public struct Nested {
        public init() {}
    }
}
