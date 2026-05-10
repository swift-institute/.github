// L1 primitive — platform-agnostic, no #if os(...) conditional.

public enum Foo {
    public struct Identifier {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
    }
}
